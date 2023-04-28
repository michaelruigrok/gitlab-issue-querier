#!/usr/bin/env raku

use lib './lib';
use JSON::Fast;
use Gitlab::Issues::Query;
use Gitlab::Issues::Request;

# Nested regex match engine
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

my \GIQ = GitlabIssueQuery;

# Behaviour corresponding to each regex match type
# Delegated to GitlabIssueQueryBuilder to assemble a series of gitlab API requests.
class GIQLActions {
	# Common structure: make all children, return as list
	method m($/) { $/.values.map(*.made); }
	# TODO: See if traits would be helpful in reducing repetition here.

	method TOP($/)      { make $/<or>.made; }
	
	# TODO: Call these compounds using :sym
	method brackets($/) { make $/<TOP>.made; }
	method or($/) { make [|] |$.m($/); }
	method and($/) { make [&] |$.m($/); }

	# Maybe "Comparison" is a better name?
	method test:sym<equals>($/) { make GIQ.new(equals => $.m($/).Map.pairs); }
	method test:sym<regex>($/)  { make GIQ.new(regex  => $.m($/).Map.pairs); }

	method test:sym<in>($/) {
		make $.m($/).map({ $/<term> => $_ , });
	}

	method list($/) { make $.m($/); }
	method term($/) { make ~$/[0]; }
}

sub MAIN(*@args) {
	my $queries = GIQL.parse(@args.join(' '), actions => GIQLActions.new).made;
	$queries.exec.map(*<web_url>).put;
}
