use Gitlab::Issues::Request;

my @GIAliases = @(
	<author author_name author_user> => 'author_username',
	<assignee assignee_name assignee_user> => 'author_username',
	<created_since> => 'created_after',
	<due> => 'due_date',
	<updated_since> => 'updated_after',
);

sub resolveAlias(Str $key) {
	for @GIAliases {
		if $key (elem) .key { return .value }
	}
	$key
}

class X::ConflictingTest is Exception {
	has Str $.test;

	method message() {
		"Two conflicting queries for property '$.test'";
	}
}

# Stores all the Queriy comparisons for a given kind of comparison
class ComparerConjunction {
	# Special Modifiable Sets for special subtypes of Issue properties
	has Set $.labels;
	has Set $.iids;
	has %.other;

	submethod BUILD(:$labels = (), :$iids = (), :$other = ()) {
		$!labels = $labels ~~ Set ?? $labels !! set($labels);
		$!iids   = $iids   ~~ Set ?? $iids   !! set($iids);
		%!other = Map.new(@$other);
	}
}

multi sub infix:<&>(ComparerConjunction $a, ComparerConjunction $b) is export {
	ComparerConjunction.new(
		other => (|$a.other.kv, |$b.other.kv),
		iids => ($a.iids (|) $b.iids),
		labels => ($a.labels (|) $b.labels),
	);
}

# Represents different kinds of comparisons ANDed together
class GIQConjunction {
	has $.equals = ComparerConjunction.new();
	has $.regex = ComparerConjunction.new();

	method addEquals($key, $value) {
		my $name = resolveAlias($key);

		if $.equals<$name>:exists {
			X::ConflictingTest.new(test => "$name").throw;
		}

		$.equals.other.push(($name => $value));;
	}

	method addRegex($key, $value) {
		$.regex.other.push($key => $value);
	}

	method and(*@queries) {
		for @queries -> $query {
			$.regex.append($query.regex);

			with $_.equals (&) $query.equals {
				X::ConflictingTest.new(test => $_).throw;
			}
			$.equals.other.append($query.equals);
		}
	}
}

multi sub infix:<&>(GIQConjunction $a!, GIQConjunction $b = GIQConjunction.new) is export is pure {
	if $a.equals.other (&) $b.equals.other -> $_ {
			X::ConflictingTest.new(test => $_.gist).throw;
	}

	GIQConjunction.new(
		equals => ($a.equals & $b.equals),
		regex  => ($a.regex  & $b.regex),
	);

}

enum TestType is export <Equals Regex>;

class GitlabIssueQuery {

	# A GIQ query is represented by a List of Expressions OR'd together.
	# In turn, each inner expression (a GIQConjunction), represents
	# a series of predicates AND'd together.
	has GIQConjunction @.options = (GIQConjunction.new,);

	multi submethod BUILD(:@!options!) {}

	multi submethod BUILD(:$equals, :$regex) {
		my $conj = GIQConjunction.new;
		@!options = ($conj);
		self.and(:$equals, :$regex);
	}

	method gist() { "GIQ<{@!options.gist}>"; }

	method or(*@queries) { 
		# To OR with other values, simply merge the list of ORs
		GitlabIssueQuery.new(options => @queries.map(|*.options));
	}

	multi method and(:$equals, :$regex) {
		for $equals // [] {
			@!options[0].addEquals(.key, .value);
		}
		for $regex // [] {
			@!options[0].addRegex(.key, .value);
		}
		return self
	}

	multi method and(*@queries) {
		# We need to move these outer &'s to the inner Conjunctions.
		# cross-product 'a & (b | c)' into '(a & b) | (a & c)'
		# (each letter represents a GIQConjunction)
		my @options = ([X] @queries.map(*.options))
			# combine inner lists of &'s into a single GIQConjunction
			.map({ [&] $_ });
		GitlabIssueQuery.new(:@options);
	}

	method exec {
		my @results = @.options.race(:1batch).map({
			|gitlabIssueRequest(|$_.equals.other);
		}).unique(as => *<id>);
	}
}

class GitlabIssueQueryBuilder is export {

	method or(*@queries)  { 
		GitlabIssueQuery.or(|@queries);
	}

	method and(*@queries) {
		GitlabIssueQuery.and(|@queries);
	}

	method testEquals(Str $key, Str $value) {
		GitlabIssueQuery.new(equals => ($key => $value));
	}

}

