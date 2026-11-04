BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>

INSERT {
	GRAPH sigdata:graph {
		?next_signature_level a sig:SignatureLevel;
			sig:levelValue ?next_signature_level_value.
		?new_signature a sig:Signature;
			sig:level ?next_signature_level;
			sig:id ?new_signature_id.
		?i sig:hasSignature ?new_signature
	}
}
WHERE {

	{
		SELECT
			?last_signature_level_value
			?i ?i_signature_0_id
			(
				GROUP_CONCAT(
					CONCAT(
						?p_o_type_sig,
						' (',
						IF(?p_o_type_sig_count > 5, 'n', STR(?p_o_type_sig_count)),
						')'
					);
					separator=";"
				) AS ?p_o_signature
			)
		WHERE {
			SELECT
				?last_signature_level_value
				?i ?i_signature_0_id ?p_o_type_sig
				(COUNT(DISTINCT ?o) AS ?p_o_type_sig_count)
			WHERE {
				SELECT
					?last_signature_level_value
					?i ?i_signature_0_id ?o
					# Targets are referenced by their full previous-level id only when that
					# level is 0 (short, readable ids). From level 2 on, the target's id is
					# replaced by '#' + SHA1(id), so ids stay bounded in length instead of
					# nesting all previous levels.
					(CONCAT(
						?p_sig,
						' [',
						IF(?last_signature_level_value < 1,
							?o_signature_id,
							CONCAT('#', SHA1(?o_signature_id))),
						']'
					) AS ?p_o_type_sig)
				WHERE {
					{
						SELECT
							?last_signature_level_value
							?i ?i_signature_0_id
							?o ?o_signature_id
							(GROUP_CONCAT(CONCAT('<',STR(?p),'>'); separator="|") AS ?p_sig)
						WHERE {
							SELECT
								?last_signature_level_value
								?i ?i_signature_0_id
								?o ?o_signature_id ?p
							WHERE {
								{	
									SELECT (MAX(?signature_level_value) AS ?last_signature_level_value)
									WHERE {
										?signature_level a sig:SignatureLevel;
											sig:levelValue ?signature_level_value.
									}
								}
								?last_signature_level a sig:SignatureLevel;
									sig:levelValue ?last_signature_level_value.
								?i sig:hasSignature ?i_signature_0.
								?i_signature_0
									sig:level siglevels:0;
									sig:id ?i_signature_0_id.
								OPTIONAL {
									?i ?p ?o.
									FILTER(?p != rdf:type).
									?o sig:hasSignature [
										sig:level ?last_signature_level;
										sig:id ?o_signature_id
									].
								}
								# FILTER NOT EXISTS {
								# 	?i ?p_spec ?o.
								# 	?p_spec rdfs:subPropertyOf+ ?p.
								# }
							}
							ORDER BY ?i ?o ?p
						}
						GROUP BY
							?last_signature_level_value
							?i ?i_signature_0_id
							?o ?o_signature_id
					}
					# FILTER NOT EXISTS {
					# 	?o rdf:type/rdfs:subClassOf+ ?o_type
					# }
				}
			}
			GROUP BY
				?last_signature_level_value
				?i ?i_signature_0_id ?p_o_type_sig
			ORDER BY ?i ?p_o_type_sig
		}
		GROUP BY
			?last_signature_level_value
			?i ?i_signature_0_id
	}

	BIND(?last_signature_level_value + 1 AS ?next_signature_level_value)
	BIND(IRI(CONCAT(STR(siglevels:), STR(?next_signature_level_value))) AS ?next_signature_level)

	BIND(
		IF(?i_signature_0_id,
			IF(BOUND(?p_o_signature),
				CONCAT(?i_signature_0_id, '; ', ?p_o_signature),
				?i_signature_0_id
			),
			IF(BOUND(?p_o_signature),
				?p_o_signature,
				''
			)
		) AS ?new_signature_id
	)
	# Level-specific IRI (see signatures-base.ru): the id alone is not unique across levels.
	BIND(IRI(CONCAT(STR(sigs:), STR(?next_signature_level_value), '/', ENCODE_FOR_URI(STR(?new_signature_id)))) AS ?new_signature)

}

