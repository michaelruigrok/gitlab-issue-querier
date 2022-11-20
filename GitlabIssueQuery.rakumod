class GIQB is export {

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

