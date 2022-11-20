#!/usr/bin/env raku

use lib './lib';
use JSON::Fast;
use Gitlab::Issues::Query;
use Gitlab::Issues::Request;

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
	my @queries = GIQL.parse(@args.join(' '), actions => GIQLActions.new).made;
	my @results = @queries.race(:1batch).map({
			|gitlabIssueRequest(|%$_);
		});
	@results.unique(:as(*<id>)).&to-json.print;
}
