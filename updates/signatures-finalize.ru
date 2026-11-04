BASE <https://w3id.org/hacid/data/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX sig: <https://w3id.org/sig/>
PREFIX sigdata: <sig/>
PREFIX siglevels: <sig/levels/>
PREFIX sigs: <sig/signatures/>

# Run once the highest level has converged (it adds no signatures over the
# previous level, see queries/convergence.rq): that level only repeats the
# previous level's partition under new names, so it is removed, and the level
# below it is marked with `sig:final true`.
#
# Called by scripts/sig-converge.sh, which checks convergence first. Level 0
# is never removed.

# 1. Mark the second-highest level as final.
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
	FILTER(?last_level_value > 0)
	GRAPH sigdata:graph {
		?final_level a sig:SignatureLevel;
			sig:levelValue ?final_level_value.
	}
	FILTER(?final_level_value = ?last_level_value - 1)
};

# 2. Remove the links to the highest-level signatures (sig:hasSignature,
# sig:hasObjectPropertySignature, sig:hasObjectPathSignature) and the
# source/target pairs of its object path signatures.
DELETE {
	GRAPH sigdata:graph {
		?x ?link ?signature.
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
	FILTER(?last_level_value > 0)
	GRAPH sigdata:graph {
		?last_level sig:levelValue ?last_level_value.
		?signature sig:level ?last_level.
		?x ?link ?signature.
	}
};

DELETE {
	GRAPH sigdata:graph {
		?pair ?p ?o.
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
	FILTER(?last_level_value > 0)
	GRAPH sigdata:graph {
		?last_level sig:levelValue ?last_level_value.
		?signature sig:level ?last_level;
			sig:hasSourceTargetPair ?pair.
		?pair ?p ?o.
	}
};

# 3. Remove the highest-level signatures.
DELETE {
	GRAPH sigdata:graph {
		?signature ?p ?o.
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
	FILTER(?last_level_value > 0)
	GRAPH sigdata:graph {
		?last_level sig:levelValue ?last_level_value.
		?signature sig:level ?last_level;
			?p ?o.
	}
};

# 4. Remove the highest level itself.
DELETE {
	GRAPH sigdata:graph {
		?last_level ?p ?o.
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
	FILTER(?last_level_value > 0)
	GRAPH sigdata:graph {
		?last_level sig:levelValue ?last_level_value;
			?p ?o.
	}
}
