IF (OBJECT_ID('dbo.fncStringSplit') IS NULL) EXEC('CREATE FUNCTION dbo.fncStringSplit() RETURNS INT AS SELECT 1')
GO

ALTER FUNCTION [dbo].[fncStringSplit] (
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


IF (NOT EXISTS(SELECT TOP(1) NULL FROM sys.types WHERE [name] = 'tpDataCompareParameters'))
BEGIN
	
	EXEC('
	CREATE TYPE dbo.tpDataCompareParameters AS TABLE (
		[Line]			 INT IDENTITY(1, 1),
		[DatabaseName]	 NVARCHAR(500),
		[SchemaName]     NVARCHAR(500),
		[TableName]      NVARCHAR(500),
		[KeyColumns]	 NVARCHAR(MAX)
	)')

END
GO


IF (OBJECT_ID('dbo.stpDataCompare') IS NULL) EXEC('CREATE PROCEDURE dbo.stpDataCompare AS SELECT 1')
GO

ALTER PROCEDURE dbo.stpDataCompare (
	@Parameters tpDataCompareParameters READONLY
)
AS
BEGIN


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
		@Counter INT = 1,
		@Total INT,

		@CurrentColumn NVARCHAR(500),
		@CounterColumn INT = 1,
		@TotalColumns INT,

		@CounterKeyColumns INT = 1,
		@NumberOfKeyColumns INT,
		@CurrentKeyColumnSource NVARCHAR(500),
		@CurrentKeyColumnDestination NVARCHAR(500)



	-------------------------------------------
	-- TEMPORARY TABLES
	-------------------------------------------

	IF (OBJECT_ID('tempdb..#Parameters') IS NOT NULL) DROP TABLE #Parameters
	CREATE TABLE #Parameters (
		[Line]			 INT IDENTITY(1, 1),
		[DatabaseName]	 NVARCHAR(500),
		[SchemaName]     NVARCHAR(500),
		[TableName]      NVARCHAR(500),
		[KeyColumns]	 NVARCHAR(MAX)
	)


	IF (OBJECT_ID('tempdb..#Columns') IS NOT NULL) DROP TABLE #Columns
	CREATE TABLE #Columns (
		[DatabaseName]	 NVARCHAR(500),
		[SchemaName]     NVARCHAR(500),
		[TableName]      NVARCHAR(500),
		[column_id]      INT,
		[ColumnName]     NVARCHAR(500),
		[ColumnTypeName] NVARCHAR(500),
		[max_length]     SMALLINT,
		[precision]      TINYINT,
		[scale]          TINYINT,
		[collation_name] NVARCHAR(500),
		[definition]     NVARCHAR(MAX),
		[is_computed]    BIT,
		[is_nullable]    BIT
	)

	IF (OBJECT_ID('tempdb..#Results') IS NOT NULL) DROP TABLE #Results
	CREATE TABLE #Results (
		[DatabaseName]		NVARCHAR(500),
		[SchemaName]		NVARCHAR(500),
		[TableName]			NVARCHAR(500),
		[KeyValue]			NVARCHAR(500),
		[ColumnName]		NVARCHAR(500),
		[ValueSource]		NVARCHAR(MAX),
		[ValueDestination]	NVARCHAR(MAX)
	)


	IF (OBJECT_ID('tempdb..#KeyColumns') IS NOT NULL) DROP TABLE #KeyColumns
	CREATE TABLE #KeyColumns (
		[Line]                 BIGINT,
		[KeyColumnSource]      NVARCHAR(500),
		[KeyColumnDestination] NVARCHAR(500)
	)


	-------------------------------------------
	-- PARAMETERS (YOU CAN CHANGE HERE)
	-------------------------------------------


	INSERT INTO #Parameters (
		DatabaseName,
		SchemaName,
		TableName,
		KeyColumns
	)
	SELECT 
		DatabaseName, 
		SchemaName, 
		TableName, 
		KeyColumns
	FROM
		@Parameters


	-------------------------------------------
	-- EXTRACT COLUMNS METADATA
	-------------------------------------------

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
	SET @Total = (@Total / 2)

	WHILE(@Counter <= @Total)
	BEGIN
	
	
		SELECT TOP(1)
			@Database = DatabaseName,
			@Schema = SchemaName,
			@Table = TableName,
			@KeyColumns = KeyColumns
		FROM
			#Parameters
		WHERE
			Line = ((@Counter - 1) * 2) + 1


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


		WHILE (@CounterColumn <= @TotalColumns)
		BEGIN
		
		
			SET @CurrentColumn = NULL
		
			SELECT TOP(1)
				@CurrentColumn = A.ColumnName
			FROM
				#Columns A
				JOIN #Columns B ON B.ColumnName = A.ColumnName AND NOT (B.DatabaseName = A.DatabaseName AND B.TableName = A.TableName AND B.SchemaName = A.SchemaName)
			WHERE
				A.column_id = @CounterColumn


			IF ((SELECT COUNT(*) FROM #KeyColumns) = 1)
			BEGIN
			
				SET @CmdKeyColumns = 'A.[' + @KeyColumns + ']'
				SET @CmdJoin = 'A.[' + @KeyColumns + '] = B.[' + @KeyColumnsDestination + ']'

			END
			ELSE BEGIN
			

				SET @CmdKeyColumns = 'CONCAT('
				SET @CmdJoin = ''
				SET @CounterKeyColumns = 1
				SET @NumberOfKeyColumns = (SELECT COUNT(*) FROM #KeyColumns)

				WHILE(@CounterKeyColumns <= @NumberOfKeyColumns)
				BEGIN
				

					SELECT
						@CurrentKeyColumnSource = KeyColumnSource,
						@CurrentKeyColumnDestination = KeyColumnDestination
					FROM
						#KeyColumns
					WHERE
						Line = @CounterKeyColumns


					SET @CmdKeyColumns += IIF(@CounterKeyColumns > 1, ','' | '', ', '') + 'A.[' + @CurrentKeyColumnSource + ']'
					SET @CmdJoin += IIF(@CounterKeyColumns > 1, ' AND ', '') + 'A.[' + @CurrentKeyColumnSource + '] = B.[' + @CurrentKeyColumnDestination + ']'

					SET @CounterKeyColumns += 1

				END


				SET @CmdKeyColumns += ')'


			END


			SET @Cmd = '
	SELECT
		''' + @Database + ''' AS [Database], ' +
		'''' + @Schema + ''' AS [Schema], ' +
		'''' + @Table + ''' AS [Table], ' +
		'' + @CmdKeyColumns + ' AS [KeyValue], ' +
		'''' + @CurrentColumn + ''' AS [ColumnName], ' +
		'CONVERT(NVARCHAR(500), A.[' + @CurrentColumn + ']) AS [ValueSource], ' +
		'CONVERT(NVARCHAR(500), B.[' + @CurrentColumn + ']) AS [ValueDestination]
	FROM
		[' + @Database + '].[' + @Schema + '].[' + @Table + '] A
		FULL JOIN [' + @DatabaseDestination + '].[' + @SchemaDestination + '].[' + @TableDestination + '] B ON ' + @CmdJoin + '		
	WHERE
		ISNULL(A.[' + @CurrentColumn + '], '''') <> ISNULL(B.[' + @CurrentColumn + '], '''')'


		
			INSERT INTO #Results
			EXEC(@Cmd)


			SET @CounterColumn += 1

		END


		SET @Counter += 1


	END


	SELECT * FROM #Results
	ORDER BY KeyValue, ColumnName


END
