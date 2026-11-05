BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>

# Run once the highest level has converged (it adds no signatures over the
# previous level, see queries/convergence.rq): the level is kept and marked
# with `sig:final true`, and its object property signatures are linked to the
# final signatures of their targets.
#
# Called by scripts/sig-converge.sh, which checks convergence first.

# 1. Mark the highest level as final.
INSERT {
	GRAPH sigdata:graph {
		?final_level sig:final true.
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
	GRAPH sigdata:graph {
		?final_level a sig:SignatureLevel;
			sig:levelValue ?level_value.
	}
	FILTER(?level_value = ?last_level_value)
};

# 2. Object property signatures point to their targets' signatures at the
# level below (sig:containsTargetNodeSignature). At the final level, which
# has the same partition as the level below, each of those has exactly one
# child signature (sig:hasParentSignature): link to it.
# DELETE {
# 	GRAPH sigdata:graph {
# 		?object_path_signature sig:containsTargetNodeSignature ?o_parent_signature
# 	}
# }
INSERT {
	GRAPH sigdata:graph {
		?object_path_signature sig:refersToTargetNodeSignature ?o_signature
	}
}
WHERE {
	GRAPH sigdata:graph {
		?final_level sig:final true.

		?object_path_signature a sig:ObjectPropertySignature;
			sig:level ?final_level;
			sig:containsTargetNodeSignature ?o_parent_signature.

		?o_signature a sig:NodeSignature;
			sig:level ?final_level;
			sig:hasParentSignature ?o_parent_signature.
	}
};

