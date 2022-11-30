use Net::HTTP::GET;
use JSON::Fast;
use URI::Query::FromHash;
use URI::Escape;

enum GISearchIn <title description>;
enum GIIssueType <issue incident test_case>;
constant GIOrderBy = do {
	enum GIOrderBy <created_at due_date label_priority milestone_due popularity priority relative_position title updated_at>;
	GIOrderBy;
}
enum GISort <asc desc>;
enum GIState <opened closed>;

class GINot {
	has Int  $assignee_id;
	has Str  $assignee_username;
	has Int  $author_id;
	has Str  $author_username;
	has List $iids where * ~~ Int;
	has List $labels where * ~~ Str;
	has Str  $milestone;
	has Str  $milestone_id;
}

sub mergeClass($type, $a, $b, $final) { 
	for $type.^attributes(:local) {
		$_.set_value($final, ($_.get_value($a) && $_.get_value($b)));
	}
}


class GitlabIssueRequest is export {
	has Str  $project;
	has Str  $group;
	has Int  $assignee_id;
	has Str  $assignee_username;
	has Int  $author_id;
	has Str  $author_username;
	has Bool $confidential;
	has Date $created_after;
	has Date $created_before;
	has Str  $due_date;
	has List $iids where { $_.all ~~ Int } = [];
	has GISearchIn  $in;
	has GIIssueType  $issue_type;
	has List  $labels where { $_.all ~~ Str } = [];
	has Str   $milestone;
	has Str   $milestone_id;
	has Str   $my_reaction_emoji;
	has Bool  $non_archived;
	has GINot $not;
	has GIOrderBy $order_by;
	has Str     $scope;
	has Str     $search;
	has GISort  $sort;
	has GIState $state;
	has Date    $updated_after;
	has Date    $updated_before;
	has Bool    $with_labels_details;
}

proto sub gitlabIssueRequest(
	Str  :$project,
	Str  :$group,
	Int  :$assignee_id,
	Str  :$assignee_username,
	Int  :$author_id,
	Str  :$author_username,
	Bool :$confidential,
	Date :$created_after,
	Date :$created_before,
	Str  :$due_date,
	List :$iids where { $_.all ~~ Int } = [],
	GISearchIn  :$in,
	GIIssueType  :$issue_type,
	List  :$labels where { $_.all ~~ Str } = [],
	Str   :$milestone,
	Str   :$milestone_id,
	Str   :$my_reaction_emoji,
	Bool  :$non_archived,
	GINot :$not,
	GIOrderBy :$order_by,
	Str     :$scope,
	Str     :$search,
	GISort  :$sort,
	GIState :$state,
	Date    :$updated_after,
	Date    :$updated_before,
	Bool    :$with_labels_details,
) is export {*}

multi sub gitlabIssueRequest(*%args) is export {

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

	my %header = PRIVATE-TOKEN => %*ENV<GITLAB_TOKEN>,;
	Net::HTTP::GET("%*ENV<GITLAB_URL>/api/v4/$path?{hash2query(%args)}",
		:%header).content(:force).&from-json;

}
