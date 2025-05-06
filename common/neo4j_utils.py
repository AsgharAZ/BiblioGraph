from neo4j import GraphDatabase
import pandas as pd
from dotenv import load_dotenv
import os
load_dotenv("common/.env")

driver = GraphDatabase.driver(os.getenv("NEO4J_URI"), auth=(os.getenv("NEO4J_NAME"), os.getenv("NEO4J_PASSWORD")))

def run_query(query, params={}):
    with driver.session() as session:
        result = session.run(query, params)
        return result.to_df()
    
    
def close_driver():
    driver.close()
    
    
class Neo4jOperation(object):
    def __init__(self, query, setup_query=None, teardown_query=None, params=None):
        self.query = query
        self.setup_query = setup_query
        self.teardown_query = teardown_query
        
    def run(self):
        # print variable name
        print(f"Running query: {self.query}")
        if self.setup_query:
            run_query(self.setup_query)
        result = run_query(self.query)
        if self.teardown_query:
            run_query(self.teardown_query)
        return result
    
    
# test the connection
if __name__ == "__main__":
    try:
        result = run_query("MATCH (n :Author) RETURN n.authorId, n.authorName, n.authorUrl LIMIT 5")
        print(result)
    except Exception as e:
        print(f"Error: {e}")
    finally:
        close_driver()
        print("Driver closed.")