
-------------------------------------------
-- CREATE PRE-REQUIRED OBJECTS
-------------------------------------------

CREATE OR ALTER FUNCTION [dbo].[fncStringSplit] (
    @Ds_Text VARCHAR(MAX),
    @Ds_Delimiter VARCHAR(100)
)
RETURNS @Results TABLE
(
    Id INT,
    Piece VARCHAR(MAX)
)
AS
BEGIN

    DECLARE
        @DsString VARCHAR(MAX),
        @DsPiece VARCHAR(MAX) = '',
        @NumberOfPieces INT = 1


    IF (LEN(@Ds_Text) > 0)
        SET @Ds_Text = @Ds_Text + @Ds_Delimiter   

    
    WHILE (LEN(@Ds_Text) > 0)
    BEGIN  
    
        
        SET @DsString = LTRIM(SUBSTRING(@Ds_Text, 1, CHARINDEX(@Ds_Delimiter, @Ds_Text) - 1))  


        IF (@DsPiece = ' ')
            SET @DsPiece = '' 
        
        
        IF ((@NumberOfPieces = 1 AND LEN(@DsPiece) > 0) OR @NumberOfPieces > 1)
        BEGIN
            
            INSERT INTO @Results ( Id, Piece )
            VALUES ( @NumberOfPieces, LTRIM(RTRIM(@DsPiece)) ) 
                
            SET @NumberOfPieces = @NumberOfPieces + 1
            
        END
        
        
        SET @DsPiece = @DsString
        SET @Ds_Text = SUBSTRING(@Ds_Text, CHARINDEX(@Ds_Delimiter, @Ds_Text) + 1, LEN(@Ds_Text))
          
    END  


    INSERT INTO @Results ( Id, Piece )
    VALUES ( @NumberOfPieces, LTRIM(RTRIM(@DsPiece)) ) 


    RETURN


END
GO



-------------------------------------------
-- VARIABLES
-------------------------------------------

DECLARE
    @Database NVARCHAR(500),
    @Schema NVARCHAR(500),
    @Table NVARCHAR(500),
    @KeyColumns VARCHAR(MAX),

    @DatabaseDestination NVARCHAR(500),
    @SchemaDestination NVARCHAR(500),
    @TableDestination NVARCHAR(500),
    @KeyColumnsDestination VARCHAR(MAX),

    @Cmd NVARCHAR(MAX),
    @CmdJoin NVARCHAR(MAX),
    @CmdKeyColumns NVARCHAR(MAX),
    @CmdWhereOnlyInLeft NVARCHAR(MAX),
    @Counter INT = 1,
    @Total INT,

    @CurrentColumn NVARCHAR(500),
    @CurrentColumnType VARCHAR(128),
    @CounterColumn INT = 1,
    @TotalColumns INT,

    @CounterKeyColumns INT = 1,
    @NumberOfKeyColumns INT,
    @CurrentKeyColumnSource NVARCHAR(500),
    @CurrentKeyColumnDestination NVARCHAR(500),

    @Debug BIT = 0



-------------------------------------------
-- TEMPORARY TABLES
-------------------------------------------

IF (OBJECT_ID('tempdb..#Parameters') IS NOT NULL) DROP TABLE #Parameters
CREATE TABLE #Parameters (
    [Line]			        INT IDENTITY(1, 1),
    [DatabaseName]	        NVARCHAR(500),
    [SchemaName]            NVARCHAR(500),
    [TableName]             NVARCHAR(500),
    [KeyColumns]	        NVARCHAR(MAX)
)


IF (OBJECT_ID('tempdb..#Columns') IS NOT NULL) DROP TABLE #Columns
CREATE TABLE #Columns (
    [DatabaseName]	        NVARCHAR(500),
    [SchemaName]            NVARCHAR(500),
    [TableName]             NVARCHAR(500),
    [column_id]             INT,
    [ColumnName]            NVARCHAR(500),
    [ColumnTypeName]        NVARCHAR(500),
    [max_length]            SMALLINT,
    [precision]             TINYINT,
    [scale]                 TINYINT,
    [collation_name]        NVARCHAR(500),
    [definition]            NVARCHAR(MAX),
    [is_computed]           BIT,
    [is_nullable]           BIT
)

IF (OBJECT_ID('tempdb..#Results') IS NOT NULL) DROP TABLE #Results
CREATE TABLE #Results (
    [DatabaseName]          NVARCHAR(500),
    [SchemaName]	        NVARCHAR(500),
    [TableName]		        NVARCHAR(500),
    [KeyValue]		        NVARCHAR(500),
    [ColumnName]	        NVARCHAR(500),
    [ValueSource]           SQL_VARIANT,
    [ValueDestination]      SQL_VARIANT,
    [Type]			        INT,
    [TypeDesc]		        NVARCHAR(100)
)


IF (OBJECT_ID('tempdb..#KeyColumns') IS NOT NULL) DROP TABLE #KeyColumns
CREATE TABLE #KeyColumns (
    [Line]                  BIGINT,
    [KeyColumnSource]       NVARCHAR(500),
    [KeyColumnDestination]  NVARCHAR(500)
)


-------------------------------------------
-- INCLUDE EXTERNAL PARAMETERS
-------------------------------------------

INSERT INTO #Parameters (
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
    '',   -- DatabaseName - NVARCHAR(500)
    'dbo',   -- SchemaName - NVARCHAR(500)
    '##Compare',    -- TableName - NVARCHAR(500)
    'SalesOrderNumber, SalesOrderLineNumber'
)


-------------------------------------------
-- EXTRACT COLUMNS METADATA
-------------------------------------------
    
-- Number of Tables being compared
SET @Total = (SELECT COUNT(*) FROM #Parameters)

WHILE (@Counter <= @Total)
BEGIN

        
    SELECT TOP(1)
        @Database = DatabaseName,
        @Schema = SchemaName,
        @Table = TableName
    FROM
        #Parameters
    WHERE
        [Line] = @Counter


    -- Create all columns metadata from compared tables
    SET @Cmd = '
    SELECT
        ''' + @Database + ''' AS DatabaseName,
        F.[name] AS SchemaName,
        B.[name] AS TableName,
        A.column_id,
        A.[name] AS ColumnName,
        C.[name] AS ColumnTypeName,
        A.max_length,
        A.[precision],
        A.scale,
        A.collation_name,
        E.[definition],
        A.is_computed,
        A.is_nullable
    FROM
        [' + @Database + '].sys.columns A
        JOIN [' + @Database + '].sys.tables B ON B.[object_id] = A.[object_id]
        JOIN [' + @Database + '].sys.types C ON C.user_type_id = A.user_type_id
        LEFT JOIN [' + @Database + '].sys.computed_columns E ON A.column_id = E.column_id AND A.[object_id] = E.[object_id]
        JOIN [' + @Database + '].sys.schemas F ON B.[schema_id] = F.[schema_id]
    WHERE
        F.[name] = ''' + @Schema + '''
        AND B.[name] = ''' + @Table + ''''


    INSERT INTO #Columns
    EXEC(@Cmd)


    SET @Counter += 1


END


-------------------------------------------
-- COMPARE DATA
-------------------------------------------

SET @Counter = 1
SET @Total = (@Total / 2) -- Every row is a table, but they work in pairs of two tables being compared

-- Iterate over every pair of tables being compared
WHILE(@Counter <= @Total)
BEGIN
    
    -- First table in the pair of two tables to be compared (Source)
    SELECT TOP(1)
        @Database = DatabaseName,
        @Schema = SchemaName,
        @Table = TableName,
        @KeyColumns = KeyColumns
    FROM
        #Parameters
    WHERE
        Line = ((@Counter - 1) * 2) + 1


    -- Second table in the pair of two tables to be compared (Destination)
    SELECT TOP(1)
        @DatabaseDestination = DatabaseName,
        @SchemaDestination = SchemaName,
        @TableDestination = TableName,
        @KeyColumnsDestination = KeyColumns
    FROM
        #Parameters
    WHERE
        Line = ((@Counter - 1) * 2) + 2

    
    SET @CounterColumn = 1
    
    SELECT 
        @TotalColumns = COUNT(*)
    FROM
        #Columns A
    WHERE
        A.DatabaseName = @Database
        AND A.SchemaName = @Schema
        AND A.TableName = @Table

        
        
    TRUNCATE TABLE #KeyColumns

    -- Insert the KeyColumns to be compared in JOIN clause. It splits into multiple rows in case of composite keys (multiple key columns)
    INSERT INTO #KeyColumns
    SELECT 
        ROW_NUMBER() OVER(ORDER BY A.Id) AS Line,
        A.Piece AS KeyColumnSource,
        B.Piece AS KeyColumnDestination
    FROM
        dbo.fncStringSplit(@KeyColumns, ',') A
        CROSS APPLY dbo.fncStringSplit(@KeyColumnsDestination, ',') B
    WHERE
        A.Id = B.Id


    -- If we have only 1 KeyColumn, that's easy :)
    IF ((SELECT COUNT(*) FROM #KeyColumns) = 1)
    BEGIN
            
        SET @CmdKeyColumns = 'A.[' + @KeyColumns + ']'
        SET @CmdJoin = 'A.[' + @KeyColumns + '] = B.[' + @KeyColumnsDestination + ']'
        SET @CmdWhereOnlyInLeft = 'B.[' + @KeyColumns + '] IS NULL'

    END
    ELSE BEGIN -- But if we have multiple KeyColumns, then we have way more work to do :(
            

        SET @CmdKeyColumns = 'CONCAT('
        SET @CmdJoin = ''
        SET @CmdWhereOnlyInLeft = ''
        SET @CounterKeyColumns = 1
        SET @NumberOfKeyColumns = (SELECT COUNT(*) FROM #KeyColumns)

        -- Iterate over each KeyColumn
        WHILE(@CounterKeyColumns <= @NumberOfKeyColumns)
        BEGIN
                
                
            -- Set the pair of Source and Destination KeyColumn for each interation to create the KeyColumns fieldlist and the JOIN clauses for multiple keys.
            SELECT
                @CurrentKeyColumnSource = KeyColumnSource,
                @CurrentKeyColumnDestination = KeyColumnDestination
            FROM
                #KeyColumns
            WHERE
                Line = @CounterKeyColumns


            SET @CmdKeyColumns += IIF(@CounterKeyColumns > 1, ','' | '', ', '') + 'A.[' + @CurrentKeyColumnSource + ']'
            SET @CmdJoin += IIF(@CounterKeyColumns > 1, ' AND ', '') + 'A.[' + @CurrentKeyColumnSource + '] = B.[' + @CurrentKeyColumnDestination + ']'
            SET @CmdWhereOnlyInLeft += IIF(@CounterKeyColumns > 1, ' AND ', '') + 'B.[' + @KeyColumns + '] IS NULL'

            SET @CounterKeyColumns += 1

        END


        SET @CmdKeyColumns += ')'


    END



    -- Create the full SQL query to compare all the data. This is where the magic happens :P
    SET @Cmd = '
SELECT
    ''' + @Database + ''' AS [Database], ' +
    '''' + @Schema + ''' AS [Schema], ' +
    '''' + @Table + ''' AS [Table], ' +
    '' + @CmdKeyColumns + ' AS [KeyValue], ' +
    '''' + REPLACE(REPLACE(@CmdKeyColumns, 'A.[', ''), ']', '') + ''' AS [ColumnName], ' +
    'CONVERT(SQL_VARIANT, ' + @CmdKeyColumns + ') AS [ValueSource], ' +
    'NULL AS [ValueDestination],
    1 AS [Type],
    ''1-OnlyInLeft'' AS [TypeDesc]
FROM
    [' + @Database + '].[' + @Schema + '].[' + @Table + '] A
    LEFT JOIN [' + @DatabaseDestination + '].[' + @SchemaDestination + '].[' + @TableDestination + '] B ON ' + @CmdJoin + '		
WHERE
    ' + @CmdWhereOnlyInLeft


    -- Append the results for each column comparison in the final table
    IF (@Debug = 1) PRINT @Cmd

    INSERT INTO #Results
    EXEC(@Cmd)



    -- Create the full SQL query to compare all the data. This is where the magic happens :P
    SET @Cmd = '
SELECT
    ''' + @Database + ''' AS [Database], ' +
    '''' + @Schema + ''' AS [Schema], ' +
    '''' + @Table + ''' AS [Table], ' +
    '' + REPLACE(@CmdKeyColumns, 'A.[', 'B.[') + ' AS [KeyValue], ' +
    '''' + REPLACE(REPLACE(@CmdKeyColumns, 'A.[', ''), ']', '') + ''' AS [ColumnName], ' +
    'CONVERT(SQL_VARIANT, ' + @CmdKeyColumns + ') AS [ValueSource], ' +
    'NULL AS [ValueDestination],
    2 AS [Type],
    ''2-OnlyInRight'' AS [TypeDesc]
FROM
    [' + @Database + '].[' + @Schema + '].[' + @Table + '] A
    RIGHT JOIN [' + @DatabaseDestination + '].[' + @SchemaDestination + '].[' + @TableDestination + '] B ON ' + @CmdJoin + '		
WHERE
    ' + REPLACE(@CmdWhereOnlyInLeft, 'B.[', 'A.[')


    -- Append the results for each column comparison in the final table
    IF (@Debug = 1) PRINT @Cmd

    INSERT INTO #Results
    EXEC(@Cmd)



    -- Iterate over every column in both tables being compared
    WHILE (@CounterColumn <= @TotalColumns)
    BEGIN
        
        
        SET @CurrentColumn = NULL
            

        -- Select the column to be compared in this iteration. Only columns with the same name in both tables will return.
        SELECT TOP(1)
            @CurrentColumn = A.ColumnName,
            @CurrentColumnType = A.ColumnTypeName
        FROM
            #Columns A
            JOIN #Columns B ON B.ColumnName = A.ColumnName AND NOT (B.DatabaseName = A.DatabaseName AND B.TableName = A.TableName AND B.SchemaName = A.SchemaName)
        WHERE
            A.column_id = @CounterColumn



        IF (NOT EXISTS(SELECT TOP(1) NULL FROM #KeyColumns WHERE KeyColumnSource = @CurrentColumn))
        BEGIN
            
            -- Create the full SQL query to compare all the data. This is where the magic happens :P
            SET @Cmd = '
SELECT
    ''' + @Database + ''' AS [Database], ' +
    '''' + @Schema + ''' AS [Schema], ' +
    '''' + @Table + ''' AS [Table], ' +
    '' + @CmdKeyColumns + ' AS [KeyValue], ' +
    '''' + @CurrentColumn + ''' AS [ColumnName], ' +
    'CONVERT(SQL_VARIANT, A.[' + @CurrentColumn + ']) AS [ValueSource], ' +
    'CONVERT(SQL_VARIANT, B.[' + @CurrentColumn + ']) AS [ValueDestination],
    3 AS [Type],
    ''3-DifferentData'' AS [TypeDesc]
FROM
    [' + @Database + '].[' + @Schema + '].[' + @Table + '] A
    JOIN [' + @DatabaseDestination + '].[' + @SchemaDestination + '].[' + @TableDestination + '] B ON ' + @CmdJoin + '		
WHERE
    ' + CASE 
            WHEN (@CurrentColumnType IN ('varchar', 'nvarchar', 'nchar', 'char')) THEN 'ISNULL(A.[' + @CurrentColumn + '], '''') <> ISNULL(B.[' + @CurrentColumn + '], '''')'
            WHEN (@CurrentColumnType IN ('date', 'datetime', 'timestamp')) THEN 'ISNULL(A.[' + @CurrentColumn + '], ''1900-01-01'') <> ISNULL(B.[' + @CurrentColumn + '], ''1900-01-01'')'
            ELSE 'ISNULL(A.[' + @CurrentColumn + '], -123) <> ISNULL(B.[' + @CurrentColumn + '], -123)'
        END

            -- Append the results for each column comparison in the final table
            IF (@Debug = 1) PRINT @Cmd

            INSERT INTO #Results
            EXEC(@Cmd)


        END


        SET @CounterColumn += 1

    END


    SET @Counter += 1


END



-- Display all the results, finally :D
SELECT *
FROM #Results
ORDER BY KeyValue, ColumnName
