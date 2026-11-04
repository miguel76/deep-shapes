BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>

# Computes the level after the highest existing one. The first operation adds
# the new level; every following operation works on the highest level (the
# new one, ?level) and reads the targets' signatures at the level below it
# (?previous_level).

INSERT {
	GRAPH sigdata:graph {
		?next_level a sig:SignatureLevel;
			sig:levelValue ?next_level_value.
	}
}
WHERE {
	{
		SELECT (MAX(?level_value) AS ?last_level_value)
		WHERE {
			GRAPH sigdata:graph {
				?level a sig:SignatureLevel;
					sig:levelValue ?level_value.
			}
		}
	}
	BIND(?last_level_value + 1 AS ?next_level_value)
	BIND(IRI(CONCAT(STR(siglevels:), STR(?next_level_value))) AS ?next_level)
};

INSERT {
	GRAPH sigdata:graph {
		?object_path_signature a sig:ObjectPathSignature;
			sig:level ?level;
			sig:id ?object_path_signature_id;
			sig:hasTargetSignature ?o_signature;
			sig:hasSourceTargetPair [
				sig:source ?i;
				sig:target ?o
			].
	}
}
WHERE {
	{
		SELECT
			?level_value ?level ?i ?o ?o_signature ?o_signature_id
			(GROUP_CONCAT(CONCAT('<',STR(?p),'>'); separator="|") AS ?link_signature_str)
		WHERE {
			SELECT ?level_value ?level ?i ?o ?o_signature ?o_signature_id ?p
			WHERE {
				{
					SELECT (MAX(?any_level_value) AS ?level_value)
					WHERE {
						GRAPH sigdata:graph {
							?any_level a sig:SignatureLevel;
								sig:levelValue ?any_level_value.
						}
					}
				}
				GRAPH sigdata:graph {
					?level sig:levelValue ?level_value.
					?previous_level sig:levelValue ?previous_level_value.
				}
				FILTER(?previous_level_value = ?level_value - 1)
				GRAPH ?g { ?i ?p ?o }
				FILTER(?g != sigdata:graph && ?p != rdf:type)
				GRAPH sigdata:graph {
					?o sig:hasSignature ?o_signature.
					?o_signature a sig:Signature;
						sig:level ?previous_level;
						sig:id ?o_signature_id.
				}
				# FILTER NOT EXISTS {
				# 	?i ?p_spec ?o.
				# 	?p_spec rdfs:subPropertyOf+ ?p.
				# }
			}
			ORDER BY ?i ?o ?p
		}
		GROUP BY ?level_value ?level ?i ?o ?o_signature ?o_signature_id
	}
	# Target signature ids are SHA-1 hashes, so ids don't grow with the level.
	BIND(SHA1(CONCAT(?link_signature_str, ' [', ?o_signature_id, ']')) AS ?object_path_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'object-values/', STR(?level_value), '/', ENCODE_FOR_URI(?object_path_signature_id))) AS ?object_path_signature)
};

INSERT {
	GRAPH sigdata:graph {
		?object_path_signature sig:hasMemberProperty ?p.
	}
}
WHERE {
	{
		SELECT ?object_path_signature (SAMPLE(?st) AS ?source_target)
		WHERE {
			{
				SELECT (MAX(?any_level_value) AS ?level_value)
				WHERE {
					GRAPH sigdata:graph {
						?any_level a sig:SignatureLevel;
							sig:levelValue ?any_level_value.
					}
				}
			}
			GRAPH sigdata:graph {
				?level sig:levelValue ?level_value.
				?object_path_signature a sig:ObjectPathSignature;
					sig:level ?level;
					sig:hasSourceTargetPair ?st.
			}
		}
		GROUP BY ?object_path_signature
	}
	GRAPH sigdata:graph {
		?source_target
			sig:source ?source;
			sig:target ?target.
	}
	GRAPH ?g { ?source ?p ?target }
	FILTER(?g != sigdata:graph && ?p != rdf:type).
	# FILTER NOT EXISTS {
	# 	?i ?p_spec ?o.
	# 	?p_spec rdfs:subPropertyOf+ ?p.
	# }
};

INSERT {
	GRAPH sigdata:graph {
		?object_property_signature a sig:ObjectPropertySignature;
			sig:level ?level;
			sig:id ?object_property_signature_id;
			sig:hasObjectPathSignature ?object_path_signature;
			sig:hasExactValueCount ?exact_object_value_count;
			sig:hasMinValueCount ?min_object_value_count.
		?i sig:hasObjectPropertySignature ?object_property_signature
	}
}
WHERE {
	{
		SELECT
			?level_value ?level
			?i ?object_path_signature ?object_path_signature_id
			(COUNT(DISTINCT ?o) AS ?object_value_count)
		WHERE {
			{
				SELECT (MAX(?any_level_value) AS ?level_value)
				WHERE {
					GRAPH sigdata:graph {
						?any_level a sig:SignatureLevel;
							sig:levelValue ?any_level_value.
					}
				}
			}
			GRAPH sigdata:graph {
				?level sig:levelValue ?level_value.
				?object_path_signature a sig:ObjectPathSignature;
					sig:level ?level;
					sig:id ?object_path_signature_id;
					sig:hasSourceTargetPair [
						sig:source ?i;
						sig:target ?o
					].
			}
		}
		GROUP BY
			?level_value ?level
			?i ?object_path_signature ?object_path_signature_id
	}
	VALUES ?count_limit {5}
	VALUES ?undef {UNDEF}
	BIND(IF(?object_value_count > ?count_limit, ?undef, ?object_value_count) AS ?exact_object_value_count)
	BIND(IF(?object_value_count > ?count_limit, ?count_limit + 1, ?undef) AS ?min_object_value_count)
	BIND(IF(?object_value_count > ?count_limit, 'n', STR(?object_value_count)) AS ?object_value_count_str)
	BIND(SHA1(CONCAT(?object_path_signature_id, ?object_value_count_str)) AS ?object_property_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'object-properties/', STR(?level_value), '/', ENCODE_FOR_URI(?object_property_signature_id))) AS ?object_property_signature)
};

INSERT {
	GRAPH sigdata:graph {
		?new_signature a sig:Signature;
			sig:level ?level;
			sig:id ?new_signature_id.
		?i sig:hasSignature ?new_signature
	}
}
WHERE {
	{
		SELECT
			?level_value ?level ?i ?i_signature_0_id
			(GROUP_CONCAT(?object_property_signature_id) AS ?obj_signature)
		WHERE {
			SELECT
				?level_value ?level ?i ?i_signature_0_id
				?object_property_signature ?object_property_signature_id
			WHERE {
				{
					SELECT (MAX(?any_level_value) AS ?level_value)
					WHERE {
						GRAPH sigdata:graph {
							?any_level a sig:SignatureLevel;
								sig:levelValue ?any_level_value.
						}
					}
				}
				GRAPH sigdata:graph {
					?level sig:levelValue ?level_value.
					?i sig:hasSignature ?i_signature_0.
					?i_signature_0 a sig:Signature;
						sig:level siglevels:0;
						sig:id ?i_signature_0_id.
					OPTIONAL {
						?i sig:hasObjectPropertySignature ?object_property_signature.
						?object_property_signature a sig:ObjectPropertySignature;
							sig:level ?level;
							sig:id ?object_property_signature_id.
					}
				}
			}
			ORDER BY
				?i ?object_property_signature_id
		}
		GROUP BY
			?level_value ?level ?i ?i_signature_0_id
	}

	BIND(
		SHA1(CONCAT(?i_signature_0_id, ';', COALESCE(?obj_signature, '')))
		AS ?new_signature_id
	)

	# Level-specific IRI (see signatures-base.ru): the id alone is not unique across levels.
	BIND(IRI(CONCAT(STR(sigs:), STR(?level_value), '/', ENCODE_FOR_URI(STR(?new_signature_id)))) AS ?new_signature)
};
