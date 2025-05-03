// clear the database for incidental problems
CALL apoc.periodic.iterate(
    "MATCH (n) RETURN n",
    "DETACH DELETE n",
    {batchSize: 10000, parallel: true}
);

CREATE INDEX IF NOT EXISTS FOR (a:Author) ON (a.authorId);
CREATE INDEX IF NOT EXISTS FOR (j:Journal) ON (j.journalName);
CREATE INDEX IF NOT EXISTS FOR (p:Paper) ON (p.paperId);
CREATE INDEX IF NOT EXISTS FOR (t:Topic) ON (t.topicId);

:auto LOAD CSV WITH HEADERS FROM "file:///author.csv" AS row
WITH row
// Skipping rows where Author ID or Author Name is null
WHERE row.`Author ID` IS NOT NULL AND row.`Author Name` IS NOT NULL
CALL {
    WITH row
    // MERGE (find or create) Author node based on Author ID
    MERGE (author:Author {authorId: row.`Author ID`})
    ON CREATE SET
        author.authorName = row.`Author Name`,
        author.authorUrl = row.`Author URL`
    // ON MATCH SET // Add any properties you want to update on existing nodes here
} IN TRANSACTIONS;

// Assuming Journal Name is sufficient as a unique identifier for Journal nodes.
// Journal Publisher will be stored as a property.
:auto LOAD CSV WITH HEADERS FROM "file:///journal.csv" AS row
WITH row
// Skipping rows where Journal Name is null
WHERE row.`Journal Name` IS NOT NULL
CALL {
    WITH row
    // MERGE Journal node based on Journal Name
    MERGE (journal:Journal {journalName: row.`Journal Name`})
    ON CREATE SET
        journal.journalPublisher = row.`Journal Publisher`
    // ON MATCH SET // Add any properties you want to update on existing nodes here
} IN TRANSACTIONS;

:auto LOAD CSV WITH HEADERS FROM "file:///paper.csv" AS row
WITH row
// Skipping rows where Paper ID, Paper DOI, Paper Title, or Paper Year is null
WHERE row.`Paper ID` IS NOT NULL AND row.`Paper DOI` IS NOT NULL AND row.`Paper Title` IS NOT NULL AND row.`Paper Year` IS NOT NULL
CALL {
    WITH row
    // MERGE Paper node based on Paper ID
    MERGE (paper:Paper {paperId: row.`Paper ID`})
    ON CREATE SET
        paper.paperDoi = row.`Paper DOI`,
        paper.paperTitle = row.`Paper Title`,
        paper.paperYear = toInteger(row.`Paper Year`), // Convert year to integer
        paper.paperUrl = row.`Paper URL`,
        paper.paperCitationCount = toInteger(row.`Paper Citation Count`), // Convert citation count to integer
        paper.fieldsOfStudy = row.`Fields of Study`,
        paper.journalVolume = row.`Journal Volume`,
        paper.journalDate = row.`Journal Date`
    // ON MATCH SET // Add any properties you want to update on existing nodes here
} IN TRANSACTIONS;

:auto LOAD CSV WITH HEADERS FROM "file:///topic.csv" AS row
WITH row
// Skipping rows where Topic ID or Topic Name is null
WHERE row.`Topic ID` IS NOT NULL AND row.`Topic Name` IS NOT NULL
CALL {
    WITH row
    // MERGE Topic node based on Topic ID
    MERGE (topic:Topic {topicId: row.`Topic ID`})
    ON CREATE SET
        topic.topicName = row.`Topic Name`,
        topic.topicUrl = row.`Topic URL`
    // ON MATCH SET // Add any properties you want to update on existing nodes here
} IN TRANSACTIONS;

// --- Relationships ---

:auto LOAD CSV WITH HEADERS FROM "file:///author_paper.csv" AS row
WITH row
// Skipping rows where Author ID or Paper ID is null
WHERE row.`Author ID` IS NOT NULL AND row.`Paper ID` IS NOT NULL
CALL {
    WITH row
    // Match the existing Author and Paper nodes
    MATCH (author:Author {authorId: row.`Author ID`})
    MATCH (paper:Paper {paperId: row.`Paper ID`})
    // MERGE the WROTE relationship between Author and Paper
    MERGE (author)-[:WROTE]->(paper)
} IN TRANSACTIONS;

// Relationship goes from Paper to Journal
:auto LOAD CSV WITH HEADERS FROM "file:///paper_journal.csv" AS row
WITH row
// Skipping rows where Paper ID or Journal Name is null
WHERE row.`Paper ID` IS NOT NULL AND row.`Journal Name` IS NOT NULL
CALL {
    WITH row
    // Match the existing Paper and Journal nodes
    MATCH (paper:Paper {paperId: row.`Paper ID`})
    MATCH (journal:Journal {journalName: row.`Journal Name`}) // Match journal by Name
    // MERGE the IS_PUBLISHED_IN relationship between Paper and Journal
    MERGE (paper)-[:IS_PUBLISHED_IN]->(journal)
} IN TRANSACTIONS;

// Relationship goes from the citing Paper to the referenced Paper
:auto LOAD CSV WITH HEADERS FROM "file:///paper_reference.csv" AS row
WITH row
// Skipping rows where Paper ID or Referenced Paper ID is null
WHERE row.`Paper ID` IS NOT NULL AND row.`Referenced Paper ID` IS NOT NULL
CALL {
    WITH row
    // Match the citing Paper and the referenced Paper
    MATCH (citingPaper:Paper {paperId: row.`Paper ID`})
    MATCH (referencedPaper:Paper {paperId: row.`Referenced Paper ID`})
    // MERGE the CITES relationship from citingPaper to referencedPaper
    MERGE (citingPaper)-[:CITES]->(referencedPaper)
} IN TRANSACTIONS;

// Relationship goes from Paper to Topic
:auto LOAD CSV WITH HEADERS FROM "file:///paper_topic.csv" AS row
WITH row
// Skipping rows where Paper ID or Topic ID is null
WHERE row.`Paper ID` IS NOT NULL AND row.`Topic ID` IS NOT NULL
CALL {
    WITH row
    // Match the existing Paper and Topic nodes
    MATCH (paper:Paper {paperId: row.`Paper ID`})
    MATCH (topic:Topic {topicId: row.`Topic ID`})
    // MERGE the HAS_TOPIC relationship between Paper and Topic
    MERGE (paper)-[:HAS_TOPIC]->(topic)
} IN TRANSACTIONS;
