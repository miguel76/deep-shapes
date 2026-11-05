BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sh: <http://www.w3.org/ns/shacl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>
PREFIX shapedata: <shapes/>

# Generates SHACL shapes from the final level (marked `sig:final true` by
# signatures-finalize.ru) into the named graph shapedata:graph, replacing any
# shapes generated before. Does nothing if no level is final yet.
#
# - One node shape per final node signature, `shapes/nodes/{id}`, without
#   targets, with sh:class for each member type, closed (rdf:type aside).
# - One property shape per datatype or object property signature of the node
#   signature, on the smallest property (by IRI) of its path signature (the
#   main property), with the value count as min/max count. The other
#   properties of the path signature each get a companion property shape
#   that makes them equal to the main property.
# - The constraints are qualified (sh:qualifiedValueShape,
#   sh:qualifiedMin/MaxCount, and sh:qualifiedEquals for the companions, an
#   extension of SHACL) when another property signature of the same node
#   signature shares a property with this one; otherwise they are not
#   (sh:datatype/sh:languageIn or sh:node, sh:min/maxCount, sh:equals).
#
# See docs/shapes.md for the details.

DROP SILENT GRAPH shapedata:graph;

DELETE WHERE {
	GRAPH sigdata:graph {
		?node_signature sig:hasShape ?node_shape
	}
};

# 1. Node shapes.
INSERT {
	GRAPH shapedata:graph {
		?node_shape a sh:NodeShape;
			sh:class ?type;
			sh:closed true;
			sh:ignoredProperties shapedata:ignored-properties.
		# Shared list (an IRI, so that it isn't repeated for every shape).
		shapedata:ignored-properties rdf:first rdf:type;
			rdf:rest rdf:nil.
	}
	GRAPH sigdata:graph {
		?node_signature sig:hasShape ?node_shape
	}
}
WHERE {
	GRAPH sigdata:graph {
		?final_level sig:final true.
		?node_signature a sig:NodeSignature;
			sig:level ?final_level;
			sig:id ?node_signature_id;
			sig:containsBaseNodeSignature/sig:containsTypeSignature ?type_signature.
		OPTIONAL { ?type_signature sig:hasMemberType ?type }
	}
	BIND(IRI(CONCAT(STR(shapedata:), 'nodes/', ENCODE_FOR_URI(?node_signature_id))) AS ?node_shape)
};

# 2. Property shapes, one per (node signature, property signature) and, for
# path signatures with several properties, companion shapes for the others.
# Every IRI (lists included) is derived from the ids, so a shape shared by
# several node shapes is written once.
INSERT {
	GRAPH shapedata:graph {
		?node_shape sh:property ?property_shape, ?companion_shape.

		?property_shape a sh:PropertyShape;
			sh:path ?main_property;
			# unqualified
			sh:datatype ?unqualified_datatype;
			sh:languageIn ?unqualified_language_list;
			sh:node ?unqualified_target_shape;
			sh:minCount ?min_count;
			sh:maxCount ?max_count;
			# qualified
			sh:qualifiedValueShape ?value_shape;
			sh:qualifiedMinCount ?qualified_min_count;
			sh:qualifiedMaxCount ?qualified_max_count.

		?companion_shape a sh:PropertyShape;
			sh:path ?other_property;
			sh:equals ?unqualified_main_property;
			# SHACL requires a qualified count with sh:qualifiedValueShape:
			# the same as the main property's, implied by the equality.
			sh:qualifiedValueShape ?value_shape;
			sh:qualifiedMinCount ?qualified_min_count;
			sh:qualifiedMaxCount ?qualified_max_count;
			sh:qualifiedEquals ?qualified_main_property.

		?literal_shape a sh:NodeShape;
			sh:datatype ?qualified_datatype;
			sh:languageIn ?qualified_language_list.

		?language_list rdf:first ?language;
			rdf:rest rdf:nil.
	}
}
WHERE {
	GRAPH sigdata:graph {
		?final_level sig:final true.
		?node_signature a sig:NodeSignature;
			sig:level ?final_level;
			sig:hasShape ?node_shape;
			sig:containsBaseNodeSignature ?base_node_signature.
		{
			?base_node_signature sig:containsDatatypePropertySignature ?property_signature.
			?property_signature sig:containsDatatypePathSignature ?path_signature;
				sig:hasTargetDatatype ?datatype.
			OPTIONAL { ?property_signature sig:hasTargetLanguage ?language }
			BIND('datatype-properties' AS ?kind)
		} UNION {
			?node_signature sig:containsObjectPropertySignature ?property_signature.
			?property_signature sig:containsObjectPathSignature ?path_signature;
				sig:refersToTargetNodeSignature/sig:hasShape ?target_shape.
			BIND('object-properties' AS ?kind)
		}
		?property_signature sig:id ?property_signature_id.
		OPTIONAL { ?property_signature sig:hasExactValueCount ?exact_count }
		OPTIONAL { ?property_signature sig:hasMinValueCount ?min_value_count }
	}

	{
		SELECT ?path_signature (MIN(STR(?property)) AS ?main_property_str)
		WHERE {
			GRAPH sigdata:graph {
				?path_signature sig:hasMemberProperty ?property
			}
		}
		GROUP BY ?path_signature
	}
	OPTIONAL {
		GRAPH sigdata:graph {
			?path_signature sig:hasMemberProperty ?other_property
		}
		FILTER(STR(?other_property) != ?main_property_str)
	}

	# Qualified if another property signature of the same node signature
	# (datatype or object) shares a property with this one: then the values of
	# that property are split between several property shapes.
	BIND(EXISTS {
		GRAPH sigdata:graph {
			?path_signature sig:hasMemberProperty ?shared_property.
			{
				?base_node_signature sig:containsDatatypePropertySignature ?other_signature
			} UNION {
				?node_signature sig:containsObjectPropertySignature ?other_signature
			}
			FILTER(?other_signature != ?property_signature)
			?other_signature sig:containsDatatypePathSignature|sig:containsObjectPathSignature ?other_path_signature.
			?other_path_signature sig:hasMemberProperty ?shared_property.
		}
	} AS ?qualified)

	VALUES ?undef {UNDEF}
	BIND(IRI(?main_property_str) AS ?main_property)
	BIND(IF(?qualified, ?undef, ?main_property) AS ?unqualified_main_property)
	BIND(IF(?qualified, ?main_property, ?undef) AS ?qualified_main_property)

	BIND(
		IRI(CONCAT(STR(shapedata:), IF(?qualified, 'qualified-', ''), ?kind, '/', ENCODE_FOR_URI(?property_signature_id)))
		AS ?property_shape
	)
	BIND(
		IRI(CONCAT(STR(?property_shape), '/', SHA1(STR(?other_property))))
		AS ?companion_shape
	)

	# Values: datatype and language, or the target's shape.
	BIND(
		IRI(CONCAT(STR(shapedata:), 'literals/', SHA1(CONCAT('<', STR(?datatype), '>', COALESCE(CONCAT(' @', ?language), '')))))
		AS ?any_literal_shape
	)
	BIND(IRI(CONCAT(STR(shapedata:), 'languages/', ENCODE_FOR_URI(?language))) AS ?language_list)
	BIND(IF(?qualified, ?undef, ?datatype) AS ?unqualified_datatype)
	BIND(IF(?qualified, ?undef, ?language_list) AS ?unqualified_language_list)
	BIND(IF(?qualified, ?undef, ?target_shape) AS ?unqualified_target_shape)
	BIND(IF(?qualified, ?any_literal_shape, ?undef) AS ?literal_shape)
	BIND(IF(?qualified, ?datatype, ?undef) AS ?qualified_datatype)
	BIND(IF(?qualified, ?language_list, ?undef) AS ?qualified_language_list)
	BIND(IF(?qualified, COALESCE(?literal_shape, ?target_shape), ?undef) AS ?value_shape)

	# Counts: exact, or at least 6 (no maximum) when capped.
	BIND(COALESCE(?exact_count, ?min_value_count) AS ?any_min_count)
	BIND(IF(?qualified, ?undef, ?any_min_count) AS ?min_count)
	BIND(IF(?qualified, ?undef, ?exact_count) AS ?max_count)
	BIND(IF(?qualified, ?any_min_count, ?undef) AS ?qualified_min_count)
	BIND(IF(?qualified, ?exact_count, ?undef) AS ?qualified_max_count)
};
