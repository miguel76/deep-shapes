BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>

DROP SILENT GRAPH sigdata:graph;

INSERT {
	GRAPH sigdata:graph {
		siglevels:0 a sig:SignatureLevel;
			sig:levelValue 0.
		?new_signature a sig:Signature;
			sig:level siglevels:0;
			sig:id ?new_signature_id.
		?i sig:hasSignature ?new_signature
	}
}
WHERE {

	{
		SELECT
			?i
  			?i_type_sig
			(
				GROUP_CONCAT(
					CONCAT(
						?p_o_type_sig,
						' (',
						IF(?p_o_type_sig_count > 5, 'n', STR(?p_o_type_sig_count)),
						')'
					);
					separator=";"
			) AS ?dt_signature)
		WHERE {
			SELECT
				?i ?i_type_sig ?p_o_type_sig
				(COUNT(DISTINCT ?o) AS ?p_o_type_sig_count)
			WHERE {
				SELECT
					?i ?i_type_sig ?o
					(CONCAT(?p_sig, ?o_signature_id) AS ?p_o_type_sig)
				WHERE {
					{
						SELECT
							?i ?i_type_sig ?o
							(GROUP_CONCAT(CONCAT('<',STR(?p),'>'); separator="|") AS ?p_sig)
						WHERE {
							SELECT ?i ?i_type_sig ?o ?p
							WHERE {
								{
									SELECT
										?i
										(CONCAT('a ', GROUP_CONCAT(CONCAT('<',STR(?i_type),'>'); separator=",")) AS ?i_type_sig)
									WHERE {
										SELECT DISTINCT ?i ?i_type
										WHERE {
											{
												?i ?p_out ?o
											} UNION {
												?s ?p_in ?i
												FILTER(isIRI(?i))
											}
											OPTIONAL {
												?i a ?i_type
											}
											# FILTER NOT EXISTS {
											# 	?i rdf:type/rdfs:subClassOf+ ?i_type
											# }
										}
										ORDER BY ?i ?i_type
									}
									GROUP BY ?i
								}
								OPTIONAL {
									?i ?p ?o.
									FILTER(?p != rdf:type && isLITERAL(?o)).
								}
								# FILTER NOT EXISTS {
								# 	?i ?p_spec ?o.
								# 	?p_spec rdfs:subPropertyOf+ ?p.
								# }
							}
							ORDER BY ?i ?o ?p
						}
						GROUP BY ?i ?i_type_sig ?o
					}
					BIND(DATATYPE(?o) AS ?o_type)
					BIND(LANG(?o) AS ?o_lang)
					BIND(CONCAT(' ^^<', STR(?o_type), '>', IF(?o_lang, CONCAT(' @', STR(?o_lang)), '')) AS ?o_signature_id)
					# FILTER NOT EXISTS {
					# 	?o rdf:type/rdfs:subClassOf+ ?o_type
					# }
				}
			}
			GROUP BY
				?i ?i_type_sig ?p_o_type_sig
			ORDER BY ?i ?p_o_type_sig
		}
		GROUP BY
			?i ?i_type_sig
	}

  	BIND(
		IF(BOUND(?i_type_sig),
			IF(BOUND(?dt_signature),
				CONCAT(?i_type_sig, ';', ?dt_signature),
				?i_type_sig),
			IF(BOUND(?dt_signature),
				?dt_signature,
				'')) AS ?new_signature_id)

	BIND(IRI(CONCAT(STR(sigs:), ENCODE_FOR_URI(STR(?new_signature_id)))) AS ?new_signature)

};

