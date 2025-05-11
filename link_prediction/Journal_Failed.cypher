MATCH (j:Journal)<-[:IS_PUBLISHED_IN]-(p:Paper)-[:HAS_TOPIC]->(t:Topic)
MERGE (j)-[:JOURNAL_HAS_TOPIC]->(t);

CALL gds.graph.project(
  'journalGraph2',
  ['Journal', 'Topic'],
  {
    JOURNAL_HAS_TOPIC: { orientation: 'UNDIRECTED' }
  }
) YIELD graphName, nodeCount, relationshipCount;

CALL gds.beta.pipeline.linkPrediction.create("LPP3");

CALL gds.beta.pipeline.linkPrediction.addNodeProperty(
  'LPP3',
  'gds.fastRP.mutate',
  {
    mutateProperty: 'embedding',
    embeddingDimension: 128,
    randomSeed: 42
  }
) YIELD nodePropertySteps;

CALL gds.beta.pipeline.linkPrediction.addFeature(
  'LPP3',
  'hadamard',
  {
    nodeProperties: ['embedding']
  }
) YIELD featureSteps;

CALL gds.beta.pipeline.linkPrediction.configureSplit(
  'LPP3',
  {
    testFraction: 0.25,
    trainFraction: 0.6,
    validationFolds: 3
  }
) YIELD splitConfig;

CALL gds.beta.pipeline.linkPrediction.addLogisticRegression(
  'LPP3',
  {
    batchSize: 100,
    learningRate: 0.001,
    maxEpochs: 100
  }
) YIELD parameterSpace;

call gds.beta.pipeline.linkPrediction.addRandomForest("LPP3",{numberOfDecisionTrees:10})

CALL gds.beta.pipeline.linkPrediction.train(
  'journalGraph2',
  {
    pipeline: 'LPP3',
    modelName: 'journalTopicModel_v1',
    targetRelationshipType: 'JOURNAL_HAS_TOPIC',
    metrics: ['AUCPR'],
    randomSeed: 42
  }
) YIELD modelInfo, modelSelectionStats;

//PREDICTION
CALL gds.beta.pipeline.linkPrediction.predict.stream(
  'journalGraph2',
  {
    modelName: 'journalTopicModel_v1',
    topN: 5
  }
) YIELD node1, node2, probability
RETURN gds.util.asNode(node1).topicName AS Topic1,
       gds.util.asNode(node2).topicName AS Topic2,
       probability
ORDER BY probability DESC
LIMIT 10;
