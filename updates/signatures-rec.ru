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

# Node signature of each resource: its base node signature and the set of its
# object property keys, i.e. (object path signature, target's previous-level
# signature) pairs, without counts. Resources that differ only by how many
# targets they have for some keys get the same signature; the counts are
# merged into intervals in the next step.
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
			?parent_signature
			(GROUP_CONCAT(?object_key_id) AS ?obj_signature)
		WHERE {
			SELECT DISTINCT
				?level_value ?level ?i ?base_node_signature ?base_node_signature_id
				?parent_signature ?object_key_id
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
					# The resource's signature at the previous level. Each level
					# refines the previous one, so all the resources with the
					# same signature share the same parent signature.
					?i sig:hasNodeSignature ?parent_signature.
					?parent_signature a sig:NodeSignature;
						sig:level ?previous_level.

					OPTIONAL {
						?object_path_signature a sig:ObjectPathSignature;
							sig:id ?object_path_signature_id;
							^sig:hasPathSignature [
								sig:source ?i;
								sig:target ?target
							].
						?target sig:hasNodeSignature ?target_signature.
						?target_signature sig:level ?previous_level;
							sig:id ?target_signature_id.
					}
				}
				# Target signature ids are SHA-1 hashes, so ids don't grow with the level.
				BIND(SHA1(CONCAT(?object_path_signature_id, ';', ?target_signature_id)) AS ?object_key_id)
			}
			ORDER BY
				?i ?object_key_id
		}
		GROUP BY
			?level_value ?level ?i ?base_node_signature ?base_node_signature_id
			?parent_signature
	}

	BIND(
		SHA1(CONCAT(?base_node_signature_id, ';', COALESCE(?obj_signature, '')))
		AS ?node_signature_id
	)

	# Level-specific IRI (see signatures-base.ru): the id alone is not unique across levels.
	BIND(IRI(CONCAT(STR(sigs:), 'nodes/', STR(?level_value), '/', ENCODE_FOR_URI(STR(?node_signature_id)))) AS ?node_signature)
};

# Object property signatures, one per node signature of the new level and
# object property key, with the minimal interval containing the target counts
# of its members. A count greater than 5 counts as "more than 5": the minimum
# is then at most 6 and there is no maximum.
INSERT {
	GRAPH sigdata:graph {
		?object_property_signature a sig:ObjectPropertySignature;
			sig:level ?level;
			sig:id ?object_property_signature_id;
			sig:containsObjectPathSignature ?object_path_signature;
			sig:containsTargetNodeSignature ?target_signature;
			sig:hasMinValueCount ?min_value_count;
			sig:hasMaxValueCount ?max_value_count.
		?node_signature sig:containsObjectPropertySignature ?object_property_signature
	}
}
WHERE {
	{
		SELECT
			?level_value ?level ?node_signature
			?object_path_signature ?object_path_signature_id
			?target_signature ?target_signature_id
			(MIN(?capped_value_count) AS ?min_value_count)
			(MAX(?value_count) AS ?max_member_value_count)
		WHERE {
			{
				SELECT
					?level_value ?level ?i
					?object_path_signature ?object_path_signature_id
					?target_signature ?target_signature_id
					(COUNT(DISTINCT ?target) AS ?value_count)
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
					?level_value ?level ?i
					?object_path_signature ?object_path_signature_id
					?target_signature ?target_signature_id
			}
			GRAPH sigdata:graph {
				?i sig:hasNodeSignature ?node_signature.
				?node_signature sig:level ?level.
			}
			BIND(IF(?value_count > 5, 6, ?value_count) AS ?capped_value_count)
		}
		GROUP BY
			?level_value ?level ?node_signature
			?object_path_signature ?object_path_signature_id
			?target_signature ?target_signature_id
	}
	VALUES ?undef {UNDEF}
	BIND(IF(?max_member_value_count > 5, ?undef, ?max_member_value_count) AS ?max_value_count)
	BIND(CONCAT(STR(?min_value_count), '..', COALESCE(STR(?max_value_count), '*')) AS ?interval_str)
	BIND(SHA1(CONCAT(SHA1(CONCAT(?object_path_signature_id, ';', ?target_signature_id)), ';', ?interval_str)) AS ?object_property_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'object-properties/', STR(?level_value), '/', ENCODE_FOR_URI(?object_property_signature_id))) AS ?object_property_signature)
};

INSERT {
	GRAPH sigdata:graph {
		?i sig:hasObjectPropertySignature ?object_property_signature
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
		?level sig:levelValue ?level_value.
		?node_signature a sig:NodeSignature;
			sig:level ?level;
			sig:containsObjectPropertySignature ?object_property_signature.
		?i sig:hasNodeSignature ?node_signature.
	}
};
