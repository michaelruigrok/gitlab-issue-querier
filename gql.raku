#!/usr/bin/env raku

use WWW;
use JSON::Fast;
use URI::Query::FromHash;
use URI::Escape;

sub gitlabIssueRequest(%args) {
	my $path;
	with %args<project> {
		$path = "projects/{uri-escape $_}/issues";
		%args<project>:delete;
	} orwith %args<group> {
		$path = "groups/{uri-escape $_}/issues";
		%args<group>:delete;
	} else {
		$path = "issues";
	}

	jget("%*ENV<GITLAB_URL>/api/v4/$path?{hash2query(%args)}",
		PRIVATE-TOKEN => %*ENV<GITLAB_TOKEN>
	).&to-json;
}

grammar GIQL {

	regex TOP { <or> }

	# Because each side of an 'or' is a separate web request, it has lowest precedence
	regex or {:s <and> [ [:i or] <and> ]* }
	regex and {:s [<brackets>|<test>] [ [:i and] [<brackets>|<test>] ]* }

	regex brackets { \( ' '* <TOP> ' '* \) }

	proto regex test {*}
	regex test:sym<equals> {:s <term> \= <term> }
	regex test:sym<regex>  {:s <term> \~\=? <term> }
	regex test:sym<in>     {:s <term> in <list> }

	token term {
		([<!ctrl-char> .]+)  # anything but control characters
		|
		\" ( <-["]>* ) \" # quoted values allow anything
	}
	token ctrl-char { <[ [ \] ( \) , \s ]> }
	regex list {
		\[ ' '*
		[ <term> <[,\s]>+ ]*
		  <term> <[,\s]>*
		\]
	}

}

class GIQB {

	method or(*$queries)  { 
		$queries.map(|*);
	}

	method and(*$queries) {
		# cross-product a & (b | c) into (a & b) | (a & c)
		# (each letter representing a list of requirements)
		([X] $queries)
			# combine inner &'s into single lists
			.map(*.flat);
	}

	method testEquals(Str $key, Str $value) {
		@( # List of Ors
			@( # List of Ands
				$key => $value,
			),
		);
	}

}

class GIQLActions {
	# Common structure: make all children, return as list
	method m($/) { $/.values.map(*.made); }

	method TOP($/)      { make $/<or>.made; }
	method brackets($/) { make $/<TOP>.made; }

	method or($/)  { make GIQB.or($.m($/)); }
	method and($/) { make GIQB.and($.m($/)); }

	method test:sym<equals>($/) { make GIQB.testEquals(|$.m($/)); }
	method test:sym<regex>($/)  { make GIQB.testRegex(|$.m($/)); }

	method test:sym<in>($/) {
		make $.m($/).map({ $/<term> => $_ , });
	}

	method list($/) { make $.m($/); }
	method term($/) { make ~$/[0]; }
}

sub MAIN(*@args) {
	my @queries = GIQL.parse(@args.join(' '), actions => Longer.new).made;
	for @queries {
		# say hash2query($_);
		say gitlabIssueRequest(%$_);
	}
}
