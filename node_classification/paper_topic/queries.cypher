// Clean up the database in case of errors
CALL apoc.periodic.iterate(
  "MATCH ()-[r]->() RETURN r",
  "DELETE r",
  {batchSize: 10000, parallel: false}
);
CALL apoc.periodic.iterate(
  "MATCH (n) RETURN n",
  "DELETE n",
  {batchSize: 10000, parallel: false}
);

// Create the CO_CITES relationship
// I have ommited this relation since it was creating a very very connected graph
CALL apoc.periodic.iterate(
  '
    MATCH (citing:Paper)-[:CITES]->(a:Paper),
          (citing)-[:CITES]->(b:Paper)
    WHERE id(a) < id(b)
    RETURN DISTINCT a, b
  ',
  '
    MERGE (a)-[r:CO_CITES]->(b)
    ON CREATE SET r.weight = 1
    ON MATCH SET r.weight = r.weight + 1
  ',
  {batchSize: 10000, parallel: false}
)

// Create Domain properties for each paper based on the topic domain
LOAD CSV WITH HEADERS FROM "file:///topic_domain.csv" AS row
MATCH (p:Paper)-[:HAS_TOPIC]->(t:Topic {topicName: row.topic})
WITH p, row.cluster as c
SET p.domains = coalesce(p.domains, [])
SET p.domains = apoc.coll.toSet(p.domains + [c]);
// Convert the property domains of paper to a list of integers
MATCH (p:Paper)
WHERE p.domains is not null
SET p.domains = toIntegerList(p.domains);
// Convert the property domains of paper to a binary encoding of size 20
// For example domains: [2,15,17] -> domains: [0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0]
MATCH (p:Paper)
WHERE p.domains IS NOT NULL
SET p.domainEncoding = [ i IN range(0,19) | 0 ]
WITH p
UNWIND p.domains AS domainIndex
SET p.domainEncoding = [ i IN range(0,19) | CASE WHEN i = domainIndex THEN 1 ELSE p.domainEncoding[i] END ];
// Delete domainEncoding property if any error occurs
MATCH (p:Paper)
WHERE p.domainEncoding IS NOT NULL
SET p.domainEncoding = null;

// Create a label for all papers that have the domainEncoding property
MATCH (p:Paper)
WHERE p.domainEncoding IS NOT NULL
SET p:KnownTopic;

// Create the graph projection
CALL gds.graph.project(
  'CiteGraph',
  { KnownTopic: {properties: 'domainEncoding'} },
  { CITES: {orientation: 'UNDIRECTED'} }
);

// Create the node classification pipeline
CALL gds.beta.pipeline.nodeClassification.create('paperPipe');
CALL gds.beta.pipeline.nodeClassification.addNodeProperty('paperPipe','fastRP',{embeddingDimension:32, mutateProperty:'embedding'});
CALL gds.beta.pipeline.nodeClassification.addNodeProperty('paperPipe','degree',{mutateProperty:'degree'});
CALL gds.beta.pipeline.nodeClassification.selectFeatures('paperPipe',['embedding','degree']);
// CALL gds.beta.pipeline.nodeClassification.addRandomForest('paperPipe', {numberOfDecisionTrees: 50});

// Create the node classification model
CALL gds.beta.pipeline.nodeClassification.train('CiteGraph', {
  pipeline: 'paperPipe',
  modelName: 'paperTopicModel',
  targetNodeLabels: ['KnownTopic'],
  targetProperty: 'topicId',
  randomSeed: 42,
  testFraction: 0.2,
  validationFolds: 5,
  metrics: ['ACCURACY', 'OUT_OF_BAG_ERROR']
}) YIELD modelInfo;