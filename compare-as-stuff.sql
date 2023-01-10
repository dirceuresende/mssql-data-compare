------------------------------------------------------------------
-- Created by Fabiano Amorim (https://www.linkedin.com/in/fabianoamorim/)
------------------------------------------------------------------

DECLARE @TableSource sysname = 'AdventureWorksDW2019.dbo.FactInternetSales', 
        @TableDest sysname = 'dirceuresende.dbo.FactInternetSales2',
        @KeyCols VARCHAR(8000),
        @CrossApply VARCHAR(8000),
        @TSQL VARCHAR(MAX)
        

 -- Compare columns based on PK
SET @KeyCols = STUFF((
                    SELECT 
                        ', ' + 't1.' + C.[name]
                    FROM
                        sys.indexes A
                        JOIN sys.index_columns B ON B.[object_id] = A.[object_id] AND B.index_id = A.index_id
                        JOIN sys.columns C ON C.[object_id] = A.[object_id] AND C.column_id = B.column_id
                    WHERE
                        A.is_primary_key = 1
                        AND A.[object_id] = OBJECT_ID(@TableSource)
                    ORDER BY
                        B.index_column_id ASC
                      FOR XML PATH('')
                ), 1, 2, '')


-- If PK is not available, use a fixed Key col
IF @KeyCols IS NULL
BEGIN
   SET @KeyCols = 't1.SalesOrderNumber, t1.SalesOrderLineNumber'
END


SET @CrossApply = 'CROSS APPLY (VALUES ' + STUFF((
                                                SELECT ', ' + '(''' + [name] + '''' + ', CONVERT(SQL_VARIANT, t1.' + [name] + '))'
                                                FROM
                                                    sys.all_columns A
                                                WHERE
                                                    A.[object_id] = OBJECT_ID(@TableSource)
                                                    AND COLUMNPROPERTY(A.[object_id], A.[name], 'Precision') NOT IN(-1, 2147483647)
                                                FOR XML PATH('')
                                           ), 1, 2, '') + ') AS t2 (ColumnName, ColumValue)'


SET @TSQL = 
'SELECT
    MIN(t1.Col) AS Col, ' + @KeyCols + ', t2.ColumnName, t2.ColumValue' + CHAR(13) + CHAR(10) +
'FROM (' + CHAR(13) + CHAR(10) +
'      (
            SELECT ''1-Source'' AS Col, * FROM ' + @TableSource + ' EXCEPT SELECT ''1-Source'' AS Col, * FROM ' + @TableDest + ')' + CHAR(13) + CHAR(10) +
'           UNION ALL' + CHAR(13) + CHAR(10) +
'           (SELECT ''2-Dest'' AS Col, * FROM ' + @TableDest + ' EXCEPT SELECT ''2-Dest'' AS Col, * FROM ' + @TableSource + ')' + CHAR(13) + CHAR(10) +
'      ) AS t1' + CHAR(13) + CHAR(10) + @CrossApply + CHAR(13) + CHAR(10) + 
'GROUP BY
    ' + @KeyCols + ', t2.ColumnName, t2.ColumValue' + CHAR(13) + CHAR(10) + 
'HAVING
    COUNT(*) = 1' + CHAR(13) + CHAR(10) + 
'ORDER BY
    ' + @KeyCols + ', Col' + CHAR(13) + CHAR(10)


EXEC(@TSQL)
