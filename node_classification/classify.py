import pandas as pd
from common.neo4j_utils import run_query, close_driver, Neo4jOperation

# create strongly connected components to encode the domain knowledge

create_scc_domain_query = Neo4jOperation(setup_query="""
CALL gds.graph.project(
    'authorCoauthorGraphForSCC', 
    'Author',
    {
        COAUTHORS: {
            orientation: 'UNDIRECTED'
        }
    }
);
""", query="""
CALL gds.scc.write(
    'authorCoauthorGraphForSCC', // Name of the projected graph
    {
        writeProperty: 'sccDomainId' // Property name to store the SCC component ID on Author nodes
    }
)
YIELD componentCount;
""", teardown_query="""
CALL gds.graph.drop('authorCoauthorGraphForSCC');
""")

create_embeddings_on_coauthorship_with_domain_query = Neo4jOperation(setup_query="""
CALL gds.graph.project("domain",
    {
        Author: {
            properties:["sccDomainId"]
        }  
    },
    {
        COAUTHORS: {
            orientation: "UNDIRECTED"
        }
    }
);
""", query="""
CALL gds.beta.node2vec.write(
  "domain",
  {
    embeddingDimension:8,
    writeProperty: "node2vec",
    returnFactor: 1.0,
    inOutFactor: 1.0
  }
)
YIELD nodeCount;
"""
)

extract_embeddings_and_classes_query = Neo4jOperation("""
MATCH (a: Author)
RETURN a.authorId AS authorId, a.authorName AS authorName, a.sccDomainId as domainId, a.node2vec AS embedding;
""")


# create_scc_domain_query.run()
# create_embeddings_on_coauthorship_with_domain_query.run()
data = extract_embeddings_and_classes_query.run()

from collections import Counter
domain_counts = Counter(data['domainId'])

MIN_SAMPLES_PER_CLASS = 5
filtered_data = data[data['domainId'].map(domain_counts) >= MIN_SAMPLES_PER_CLASS]


from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix

print(filtered_data.describe())
print(filtered_data.head(5))
print(len(filtered_data))
X = filtered_data['embedding'].to_list()
Y = filtered_data['domainId'].to_list()

x_train, x_test, y_train, y_test = train_test_split(X, Y, test_size=0.4, train_size=0.6, random_state=0)
rf = RandomForestClassifier()
rf.fit(x_train, y_train)
y_pred = rf.predict(x_test)
print("Confusion Matrix:")
print(confusion_matrix(y_test, y_pred))
print("Classification Report:")
print(classification_report(y_test, y_pred))



# unique classes in the domainId column
print(len(filtered_data['domainId'].unique()))