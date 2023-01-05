
-------------------------------------------
-- PARAMETERS (YOU CAN CHANGE HERE)
-------------------------------------------

DECLARE @MyParameters AS tpDataCompareParameters

INSERT INTO @MyParameters (
	DatabaseName,
	SchemaName,
	TableName,
	KeyColumns
)
VALUES
(
	'AdventureWorksDW2019',   -- DatabaseName - NVARCHAR(500)
	'dbo',   -- SchemaName - NVARCHAR(500)
	'FactInternetSales',    -- TableName - NVARCHAR(500)
	'SalesOrderNumber, SalesOrderLineNumber'
),
(
	'dirceuresende',   -- DatabaseName - NVARCHAR(500)
	'dbo',   -- SchemaName - NVARCHAR(500)
	'FactInternetSales2',    -- TableName - NVARCHAR(500)
	'SalesOrderNumber, SalesOrderLineNumber'
)

EXEC dbo.stpDataCompare 
	@Parameters = @MyParameters  -- tpDataCompareParameters
