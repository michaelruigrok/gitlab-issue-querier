#!/usr/bin/env raku

use WWW;
use JSON::Fast;
use URI::Query::FromHash;
use URI::Escape;

sub gqlRequest(%args) {
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

grammar GQL {

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

class Longer {
	method TOP($/)      { make $/<or>.made; }
	method brackets($/) { make $/<TOP>.made; }

	method or($/)  { make $/.values.map(|*.made); }
	method and($/) {
		# cross-product a & (b | c) into (a & b) | (a & c)
		# (each letter representing a list of requirements)
		make [X] $/.values.map(*.made)
			# combine inner &'s into single lists
			.map(*.flat);
	}

	method test:sym<equals>($/) {
		make @(
			@( [=>] $/<term>.map(*.made) ),
		);
	}
	# method test:sym<regex>($/)  { make [~~] $/<term>; }
	method test:sym<in>($/)     {
		make $/.<list>.map(*.made)
			.map({
					@( $/<term> => $_ ),
			});
		make $/<term>.made (elem) $/<list>.made;
	}

	# method list($/) { make $/<term>.map(*.made); }
	method term($/) { make ~$/[0]; }
}

sub MAIN(*@args) {
	my @queries = GQL.parse(@args.join(' '), actions => Longer.new).made;
	for @queries {
		# say hash2query($_);
		say gqlRequest(%$_);
	}
}
