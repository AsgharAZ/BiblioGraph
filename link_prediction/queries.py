import pandas as pd
from common.neo4j_utils import run_query, close_driver, Neo4jOperation

FEATURE_SET_RATIO = 0.5
TRAIN_TEST_RATIO = 1 - FEATURE_SET_RATIO

create_coauthorship_query = Neo4jOperation("""
MATCH (s1 :Author)-[:WROTE]->(:Paper)<-[:WROTE]-(s2 :Author)
WHERE s1 <> s2
WITH s1, s2
MERGE (s1)-[:COAUTHORS]->(s2);
""", setup_query="""
MATCH (s1 :Author)-[r:COAUTHORS]->(s2 :Author)
DELETE r;
""")


create_feature_set_query = Neo4jOperation(f"""
MATCH (s1 :Author)-[:COAUTHORS]->(s2 :Author)
WITH s1, s2
ORDER BY s1.id,s2.id
WHERE rand() <= {FEATURE_SET_RATIO}
MERGE (s1)-[:FEATURE_REL]->(s2);
""", setup_query="""
MATCH (s1 :Author)-[r:FEATURE_REL]->(s2 :Author)
DELETE r;
""")

create_train_test_and_return_size_query = Neo4jOperation("""
MATCH (s1)-[:COAUTHORS]->(s2)
WHERE NOT EXISTS {(s1)-[:FEATURE_REL]->(s2)}
MERGE (s1)-[r:TEST_TRAIN]->(s2)
RETURN count(r) AS result;
""", setup_query="""
MATCH (s1)-[r:TEST_TRAIN]->(s2)
DELETE r;
""")

create_negative_train_test_query = Neo4jOperation("""
MATCH (s1 :Author),(s2 :Author)
WHERE NOT EXISTS {{(s1)-[:COAUTHORS]-(s2)}} 
      AND s1 < s2
      AND rand() <= {NEGATIVE_SAMPLE_RATIO}
WITH s1,s2
LIMIT {NEGATIVE_SAMPLE_LIMIT}
MERGE (s1)-[:NEGATIVE_TEST_TRAIN]->(s2);
""".format(NEGATIVE_SAMPLE_LIMIT=int(50000*(TRAIN_TEST_RATIO)), NEGATIVE_SAMPLE_RATIO=TRAIN_TEST_RATIO))

set_network_distance_query = Neo4jOperation("""
MATCH (s1)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2)
MATCH p = shortestPath((s1)-[:FEATURE_REL*]-(s2))
WITH r, length(p) AS networkDistance
SET r.networkDistance = networkDistance
""", setup_query="""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
REMOVE r.networkDistance
""")

set_preferencial_attachment_query = Neo4jOperation("""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2)
WITH r, count{ (s1)-[:FEATURE_REL]-() } * 
        count{ (s2)-[:FEATURE_REL]-() } AS preferentialAttachment
SET r.preferentialAttachment = preferentialAttachment
""", setup_query="""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
REMOVE r.preferentialAttachment
""")

set_common_neighbors_query = Neo4jOperation("""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2)
OPTIONAL MATCH (s1)-[:FEATURE_REL]-(neighbor)-[:FEATURE_REL]-(s2)
WITH r, count(distinct neighbor) AS commonNeighbor
SET r.commonNeighbor = commonNeighbor
""", setup_query="""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
REMOVE r.commonNeighbor
""")

set_adamic_adar_query = Neo4jOperation("""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
OPTIONAL MATCH (s1)-[:FEATURE_REL]-(neighbor)-[:FEATURE_REL]-(s2)
WITH r, collect(distinct neighbor) AS commonNeighbors
UNWIND commonNeighbors AS cn
WITH r, count{ (cn)-[:FEATURE_REL]-() } AS neighborDegree
WITH r, sum(1 / log(neighborDegree)) AS adamicAdar
SET r.adamicAdar = adamicAdar;
""", setup_query="""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
REMOVE r.adamicAdar
""")

set_clustering_coefficient_query = Neo4jOperation("""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
OPTIONAL MATCH (s1)-[:FEATURE_REL]-(neighbor)-[:FEATURE_REL]-(s2)
WITH r, collect(distinct neighbor) AS commonNeighbors, 
        count(distinct neighbor) AS commonNeighborCount
OPTIONAL MATCH (x)-[cr:FEATURE_REL]->(y)
WHERE x IN commonNeighbors AND y IN commonNeighbors
WITH r, commonNeighborCount, count(cr) AS commonNeighborRels
WITH r, CASE WHEN commonNeighborCount < 2 THEN 0 ELSE
   toFloat(commonNeighborRels) / (commonNeighborCount * 
                 (commonNeighborCount - 1) / 2) END as clusteringCoefficient
SET r.clusteringCoefficient = clusteringCoefficient
""", setup_query="""
MATCH (s1 :Author)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2 :Author)
REMOVE r.clusteringCoefficient
""")


extract_features_query = Neo4jOperation("""
MATCH (s1)-[r:TEST_TRAIN|NEGATIVE_TEST_TRAIN]->(s2)
WITH r.networkDistance AS networkDistance,
    r.preferentialAttachment AS preferentialAttachment,
    r.commonNeighbor AS commonNeighbor,
    r.adamicAdar  AS adamicAdar,
    CASE WHEN r:TEST_TRAIN THEN 1 ELSE 0 END as output
RETURN networkDistance, preferentialAttachment, commonNeighbor,
    adamicAdar, output     
""")                                        

def get_data(rerun: bool = False) -> pd.DataFrame:
    try:
        if rerun:
            create_coauthorship_query.run()
            create_feature_set_query.run()
            positive_size = create_train_test_and_return_size_query.run()
            print(f"Positive size: {positive_size}")
            positive_size = positive_size.iloc[0]['result']
            print(f"Positive size: {positive_size}")
            # create_negative_train_test_query.query.replace("NEGATIVE_SAMPLE_LIMIT", str(int(positive_size) * NEGATIVE_SAMPLE_RATIO))
            create_negative_train_test_query.run()
            set_network_distance_query.run()
            set_preferencial_attachment_query.run()
            set_common_neighbors_query.run()
            set_adamic_adar_query.run()
            # set_clustering_coefficient_query.run() TODO: uncomment this line to add clustering coefficient feature
        return extract_features_query.run()
    except Exception as e:
        raise e
    finally:
        close_driver()
        
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score

def predict():
    train_test_data = get_data(rerun=True)
    
    print(train_test_data.describe())
    print(train_test_data.head(10))
    
    X = train_test_data.drop('output', axis=1)
    Y = train_test_data['output'].to_list()
    
    x_train, x_test, y_train, y_test = train_test_split(X, Y, test_size=0.4, train_size=0.6, random_state=0)
    rf = RandomForestClassifier(n_estimators=100, random_state=0)
    rf.fit(x_train, y_train)
    y_pred = rf.predict(x_test)
    print("Confusion Matrix:")
    print(confusion_matrix(y_test, y_pred))
    print("Classification Report:")
    print(classification_report(y_test, y_pred))
    print("Accuracy:")
    print(accuracy_score(y_test, y_pred))
    return rf, x_test, y_test, y_pred

    
if __name__ == "__main__":
    predict()