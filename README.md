# BiblioGraph
This project applies machine learning techniques to a bibliographic dataset using graph-based approaches with Neo4j and Python. It involves data preprocessing, graph construction, and implementing node classification and link prediction tasks to explore research patterns, collaborations, and topic evolution.


## Link prediction
Make sure to check `common/.env` file. If running `link_prediction/queries.py` causes import issues then try:
```
python -m link_prediction.queries
```