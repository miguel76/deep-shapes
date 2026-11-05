BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>
PREFIX stpairs: <sig/source-target-pairs/>

DROP SILENT GRAPH sigdata:graph;

# Shapes generated from the old signatures (updates/shapes.ru) are stale, and
# would otherwise be signed as data.
DROP SILENT GRAPH <shapes/graph>;

INSERT DATA {
	GRAPH sigdata:graph {
		siglevels:0 a sig:SignatureLevel;
			sig:levelValue 0.
	}
};

INSERT {
	GRAPH sigdata:graph {
		?i_type_signature a sig:TypeSignature;
			sig:id ?i_type_signature_id.
		?i sig:hasTypeSignature ?i_type_signature
	}
}
WHERE {
	{
		SELECT
			?i
			(SHA1(COALESCE(GROUP_CONCAT(CONCAT('<',STR(?i_type),'>')), '')) AS ?i_type_signature_id)
		WHERE {
			SELECT DISTINCT ?i ?i_type
			WHERE {
				GRAPH ?g {
					{
						?i ?p_out ?o
					} UNION {
						?s ?p_in ?i
						FILTER(isIRI(?i) || isBLANK(?i))
					}
				}
				FILTER(?g != sigdata:graph)
				OPTIONAL {
					GRAPH ?g_type { ?i a ?i_type }
					FILTER(?g_type != sigdata:graph)
				}
				# FILTER NOT EXISTS {
				# 	?i rdf:type/rdfs:subClassOf+ ?i_type
				# }
			}
			ORDER BY ?i ?i_type
		}
		GROUP BY ?i
	}
	BIND(IRI(CONCAT(STR(sigs:), 'types/', ENCODE_FOR_URI(STR(?i_type_signature_id)))) AS ?i_type_signature)
};

INSERT {
	GRAPH sigdata:graph {
		?i_type_signature sig:hasMemberType ?i_type
	}
}
WHERE {
	{
		SELECT ?i_type_signature (SAMPLE(?i_member) AS ?i)
		WHERE {
			?i_member sig:hasTypeSignature ?i_type_signature.
		}
		GROUP BY ?i_type_signature
	}
	?i a ?i_type.
	# FILTER NOT EXISTS {
	# 	?i rdf:type/rdfs:subClassOf+ ?i_type
	# }
};

INSERT {
	GRAPH sigdata:graph {
		?datatype_path_signature a sig:DatatypePathSignature;
			sig:id ?datatype_path_signature_id.
		?source_target_pair a sig:SourceTargetPair;
			sig:source ?i;
			sig:target ?o;
			sig:hasPathSignature ?datatype_path_signature.
	}
}
WHERE {
	{
		SELECT
			?i ?o
			(GROUP_CONCAT(CONCAT('<',STR(?p),'>'); separator="|") AS ?link_signature_str)
		WHERE {
			SELECT ?i ?o ?p
			WHERE {
				GRAPH ?g { ?i ?p ?o }
				FILTER(?g != sigdata:graph && ?p != rdf:type && isLITERAL(?o)).
				# FILTER NOT EXISTS {
				# 	?i ?p_spec ?o.
				# 	?p_spec rdfs:subPropertyOf+ ?p.
				# }
			}
			ORDER BY ?i ?o ?p
		}
		GROUP BY ?i ?o
	}
	BIND(SHA1(?link_signature_str) AS ?datatype_path_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'datatype-paths/', ENCODE_FOR_URI(?datatype_path_signature_id))) AS ?datatype_path_signature)
	BIND(DATATYPE(?o) AS ?o_type)
	BIND(LANG(?o) AS ?o_lang)
	BIND(CONCAT(' ^^<', STR(?o_type), '>', IF(?o_lang, CONCAT(' @', STR(?o_lang)), '')) AS ?o_signature_str)
	BIND(IRI(CONCAT(STR(stpairs:), SHA1(CONCAT(STR(?i), ' "', STR(?o), '"', ?o_signature_str)))) AS ?source_target_pair)
};

INSERT {
	GRAPH sigdata:graph {
		?datatype_path_signature
			sig:hasMemberProperty ?p;
	}
}
WHERE {
	{
		SELECT ?datatype_path_signature (SAMPLE(?st) AS ?source_target)
		WHERE {
			?datatype_path_signature a sig:DatatypePathSignature;
				^sig:hasPathSignature ?st.
		}
		GROUP BY ?datatype_path_signature
	}
	?source_target
		sig:source ?source;
		sig:target ?target.
	?source ?p ?target.
	FILTER(?p != rdf:type).
	# FILTER NOT EXISTS {
	# 	?i ?p_spec ?o.
	# 	?p_spec rdfs:subPropertyOf+ ?p.
	# }
};

INSERT {
	GRAPH sigdata:graph {
		?datatype_property_signature a sig:DatatypePropertySignature;
			sig:id ?datatype_property_signature_id;
			sig:containsDatatypePathSignature ?datatype_path_signature;
			sig:hasTargetDatatype ?o_type;
			sig:hasTargetLanguage ?o_lang_if_any;
			sig:hasExactValueCount ?exact_datatype_value_count;
			sig:hasMinValueCount ?min_datatype_value_count.
		?i sig:hasDatatypePropertySignature ?datatype_property_signature
	}
}
WHERE {
	{
		SELECT
			?i ?datatype_path_signature ?datatype_path_signature_id
			?o_type ?o_lang
			(COUNT(DISTINCT ?o) AS ?datatype_value_count)
		WHERE {
			GRAPH sigdata:graph {
				?datatype_path_signature a sig:DatatypePathSignature;
					sig:id ?datatype_path_signature_id;
					^sig:hasPathSignature [
						sig:source ?i;
						sig:target ?o
					].
			}
			# The path signature has only the properties: the datatype and
			# language of the literals are part of the property signature.
			BIND(DATATYPE(?o) AS ?o_type)
			BIND(LANG(?o) AS ?o_lang)
		}
		GROUP BY
			?i ?datatype_path_signature ?datatype_path_signature_id
			?o_type ?o_lang
	}
	BIND(CONCAT(' ^^<', STR(?o_type), '>', IF(?o_lang != '', CONCAT(' @', ?o_lang), '')) AS ?o_signature_str)
	BIND(IF(?o_lang != '', ?o_lang, ?undef) AS ?o_lang_if_any)
	VALUES ?count_limit {5}
	VALUES ?undef {UNDEF}
	BIND(IF(?datatype_value_count > ?count_limit, ?undef, ?datatype_value_count) AS ?exact_datatype_value_count)
	BIND(IF(?datatype_value_count > ?count_limit, ?count_limit + 1, ?undef) AS ?min_datatype_value_count)
	BIND(IF(?datatype_value_count > ?count_limit, 'n', STR(?datatype_value_count)) AS ?datatype_value_count_str)
	BIND(SHA1(CONCAT(?datatype_path_signature_id, ';', ?o_signature_str, ';', ?datatype_value_count_str)) AS ?datatype_property_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'datatype-properties/', ENCODE_FOR_URI(?datatype_property_signature_id))) AS ?datatype_property_signature)
};


INSERT {
	GRAPH sigdata:graph {
		?base_node_signature a sig:BaseNodeSignature;
			sig:id ?base_node_signature_id;
			sig:containsTypeSignature ?i_type_signature.
		?i sig:hasBaseNodeSignature ?base_node_signature.
		?node_signature a sig:NodeSignature;
			sig:level siglevels:0;
			sig:id ?base_node_signature_id;
			sig:containsBaseNodeSignature ?base_node_signature.
		?i sig:hasNodeSignature ?node_signature
	}
}
WHERE {
	{
		SELECT
			?i ?i_type_signature ?i_type_signature_id
			(GROUP_CONCAT(?datatype_property_signature_id) AS ?dt_signature)
		WHERE {
			SELECT
				?i ?i_type_signature ?i_type_signature_id
				?datatype_property_signature ?datatype_property_signature_id
			WHERE {
				GRAPH sigdata:graph {
					?i sig:hasTypeSignature ?i_type_signature.
					?i_type_signature sig:id ?i_type_signature_id.
					OPTIONAL {
						?i sig:hasDatatypePropertySignature ?datatype_property_signature.
						?datatype_property_signature a sig:DatatypePropertySignature;
							sig:id ?datatype_property_signature_id.
					}
				}
			}
			ORDER BY
				?i ?datatype_property_signature_id
		}
		GROUP BY
			?i ?i_type_signature ?i_type_signature_id
	}

  	BIND(
		SHA1(CONCAT(?i_type_signature_id, ';', COALESCE(?dt_signature, '')))
		AS ?base_node_signature_id
	)

	BIND(IRI(CONCAT(STR(sigs:), 'base-nodes/', ENCODE_FOR_URI(STR(?base_node_signature_id)))) AS ?base_node_signature)

	# The level is part of the signature IRI: the same id string can occur at
	# several levels (e.g. a resource without object links keeps its level-0 id
	# at every level), and a shared node would end up with several sig:level
	# values, making other resources appear to have several signatures per level.
	BIND(IRI(CONCAT(STR(sigs:), 'nodes/0/', ENCODE_FOR_URI(STR(?base_node_signature_id)))) AS ?node_signature)

};

INSERT {
	GRAPH sigdata:graph {
		?base_node_signature sig:containsDatatypePropertySignature ?datatype_property_signature
	}
}
WHERE {
	{
		SELECT ?base_node_signature (SAMPLE(?i_member) AS ?i)
		WHERE {
			?i_member sig:hasBaseNodeSignature ?base_node_signature
		}
		GROUP BY ?base_node_signature
	}
	GRAPH sigdata:graph {
		?i sig:hasDatatypePropertySignature ?datatype_property_signature
	}
};

INSERT {
	GRAPH sigdata:graph {
		?object_path_signature a sig:ObjectPathSignature;
			sig:id ?object_path_signature_id.
		?source_target_pair a sig:SourceTargetPair;
			sig:source ?i;
			sig:target ?o;
			sig:hasPathSignature ?object_path_signature.
	}
}
WHERE {
	{
		SELECT
			?i ?o
			(GROUP_CONCAT(CONCAT('<',STR(?p),'>'); separator="|") AS ?link_signature_str)
		WHERE {
			SELECT ?i ?o ?p
			WHERE {
				GRAPH ?g { ?i ?p ?o }
				FILTER(?g != sigdata:graph && ?p != rdf:type && !isLITERAL(?o))
			}
			ORDER BY ?i ?o ?p
		}
		GROUP BY ?i ?o
	}
	BIND(SHA1(?link_signature_str) AS ?object_path_signature_id)
	BIND(IRI(CONCAT(STR(sigs:), 'object-paths/', ENCODE_FOR_URI(?object_path_signature_id))) AS ?object_path_signature)
	BIND(IRI(CONCAT(STR(stpairs:), SHA1(CONCAT(STR(?i), ' "', STR(?o))))) AS ?source_target_pair)
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
			GRAPH sigdata:graph {
				?object_path_signature a sig:ObjectPathSignature;
					^sig:hasPathSignature ?st.
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

