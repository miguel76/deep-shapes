BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>
PREFIX stpairs: <sig/source-target-pairs/>

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
		?object_property_signature a sig:ObjectPropertySignature;
			sig:level ?level;
			sig:id ?object_property_signature_id;
			sig:containsObjectPathSignature ?object_path_signature;
			sig:containsTargetNodeSignature ?target_signature;
			sig:hasExactValueCount ?exact_object_value_count;
			sig:hasMinValueCount ?min_object_value_count.
		?i sig:hasObjectPropertySignature ?object_property_signature
	}
}
WHERE {
	{
		SELECT
			?level_value ?level
			?i
			?object_path_signature ?object_path_signature_id
			?target_signature ?target_signature_id
			(COUNT(DISTINCT ?target) AS ?object_value_count)
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
					sig:id ?object_path_signature_id;
					^sig:hasPathSignature [
						sig:source ?i;
						sig:target ?target
					].
				?previous_level
					sig:levelValue ?previous_level_value;
					^sig:level ?target_signature.
				FILTER(?previous_level_value = ?level_value - 1)
				?target sig:hasNodeSignature ?target_signature.
				?target_signature sig:id ?target_signature_id.
			}
		}
		GROUP BY
			?level_value ?level
			?i ?object_path_signature ?object_path_signature_id
			?target_signature ?target_signature_id
	}
	VALUES ?count_limit {5}
	VALUES ?undef {UNDEF}
	BIND(IF(?object_value_count > ?count_limit, ?undef, ?object_value_count) AS ?exact_object_value_count)
	BIND(IF(?object_value_count > ?count_limit, ?count_limit + 1, ?undef) AS ?min_object_value_count)
	BIND(IF(?object_value_count > ?count_limit, 'n', STR(?object_value_count)) AS ?object_value_count_str)
	BIND(SHA1(CONCAT(?object_path_signature_id, ';', ?target_signature_id, ';', ?object_value_count_str)) AS ?object_property_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'object-properties/', STR(?level_value), '/', ENCODE_FOR_URI(?object_property_signature_id))) AS ?object_property_signature)
};

INSERT {
	GRAPH sigdata:graph {
		?node_signature a sig:NodeSignature;
			sig:level ?level;
			sig:id ?node_signature_id;
			sig:hasParentSignature ?parent_signature;
			sig:containsBaseNodeSignature ?base_node_signature.
		?i sig:hasNodeSignature ?node_signature
	}
}
WHERE {
	{
		SELECT
			?level_value ?level ?i ?base_node_signature ?base_node_signature_id
			(GROUP_CONCAT(?object_property_signature_id) AS ?obj_signature)
		WHERE {
			SELECT
				?level_value ?level ?i ?base_node_signature ?base_node_signature_id
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
					?i sig:hasBaseNodeSignature ?base_node_signature.
					?base_node_signature sig:id ?base_node_signature_id.

					?previous_level sig:levelValue ?previous_level_value.
					FILTER(?previous_level_value = ?level_value - 1)
					?i sig:hasNodeSignature ?i_parent_signature.
					?i_parent_signature sig:level ?previous_level;
						sig:id ?i_parent_signature_id.

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
			?level_value ?level ?i ?base_node_signature ?base_node_signature_id
	}

	BIND(
		SHA1(CONCAT(?base_node_signature_id, ';', COALESCE(?obj_signature, '')))
		AS ?node_signature_id
	)

	# Level-specific IRI (see signatures-base.ru): the id alone is not unique across levels.
	BIND(IRI(CONCAT(STR(sigs:), 'nodes/', STR(?level_value), '/', ENCODE_FOR_URI(STR(?node_signature_id)))) AS ?node_signature)
};

INSERT {
	GRAPH sigdata:graph {
		?node_signature sig:containsObjectPropertySignature ?object_property_signature
	}
}
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
		?level sig:levelValue ?level_value;
			^sig:level ?node_signature, ?object_property_signature.
		?i sig:hasNodeSignature ?node_signature;
			sig:hasObjectPropertySignature ?object_property_signature.
	}
};
