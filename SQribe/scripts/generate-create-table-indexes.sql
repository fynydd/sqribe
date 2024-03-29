CREATE TABLE #Results
(
    [SCHEMA_NAME] nvarchar(4000),
    [TABLE_NAME] nvarchar(4000),
    [Indexname] nvarchar(4000),
    [CreateIndex] nvarchar(max),
    [IsPrimaryXml] int,
    [PrimaryXmlIndexId] int,
    [XmlSecondaryTypeDesc] varchar(2000),
    [PrimaryXmlIndexName] varchar(2000)
);

declare @SchemaName varchar(100)
declare @TableName varchar(256)
declare @IndexName varchar(256)
declare @ColumnName varchar(100)
declare @is_unique varchar(100)
declare @IndexTypeDesc varchar(100)
declare @FileGroupName varchar(100)
declare @is_disabled varchar(100)
declare @IndexOptions varchar(max)
declare @IndexColumnId int
declare @IsDescendingKey int 
declare @IsPrimaryXml int 
declare @PrimaryXmlIndexId int
declare @PrimaryXmlIndexName varchar(2000)
declare @XmlSecondaryTypeDesc varchar(2000)
declare @IsIncludedColumn int
declare @TSQLScripCreationIndex varchar(max)
declare @TSQLScripDisableIndex varchar(max)
declare @FilterDefinition varchar(2000)

declare CursorIndex cursor for
select schema_name(t.schema_id) [schema_name], t.name, ix.name as 'index_name', ix.filter_definition,
        case when xi.xml_index_type IS NULL AND ix.is_unique = 1 then 'UNIQUE ' else '' END +
        case when xi.xml_index_type = 0 then 'PRIMARY ' else '' END as 'index_type'
     , ix.type_desc, '' +
                     CASE when ix.type_desc LIKE '%CLUSTERED COLUMNSTORE' THEN
                                  'COMPRESSION_DELAY=' + CAST(ix.compression_delay AS varchar(255))
                          ELSE
                                  case when ix.is_padded=1 then 'PAD_INDEX=ON, ' else 'PAD_INDEX=OFF, ' end
                                  + case when ix.allow_page_locks=1 then 'ALLOW_PAGE_LOCKS=ON, ' else 'ALLOW_PAGE_LOCKS=OFF, ' end
                                  + case when ix.allow_row_locks=1 then  'ALLOW_ROW_LOCKS=ON, ' else 'ALLOW_ROW_LOCKS=OFF, ' end
                                  + case when INDEXPROPERTY(t.object_id, ix.name, 'IsStatistics') = 1 then 'STATISTICS_NORECOMPUTE=ON, ' else 'STATISTICS_NORECOMPUTE=OFF, ' end
                                  + case when ix.ignore_dup_key=1 then 'IGNORE_DUP_KEY=ON, ' else 'IGNORE_DUP_KEY=OFF, ' end
                                  + case when ix.compression_delay is not null then ('COMPRESSION_DELAY=' + CAST(ix.compression_delay AS varchar(255)) + ', ') else '' end
                                  + 'SORT_IN_TEMPDB=OFF, FILLFACTOR=' + CONVERT(VARCHAR(5), CASE WHEN ix.fill_factor = 0 THEN 100 ELSE ix.fill_factor END)
                         END AS IndexOptions
     , ix.is_disabled, FILEGROUP_NAME(ix.data_space_id) FileGroupName, xi.xml_index_type, xi.using_xml_index_id, xi2.name as 'xml_index_name', xi.secondary_type_desc
from sys.tables t
         inner join sys.indexes ix on t.object_id=ix.object_id
         left join sys.xml_indexes xi on xi.name=ix.name
         left join sys.xml_indexes xi2 on xi2.index_id=xi.using_xml_index_id and xi2.object_id=xi.object_id
where ix.type>0 and ix.is_primary_key=0 and ix.is_unique_constraint=0
  and t.is_ms_shipped=0 and t.name<>'sysdiagrams' and ix.data_space_id < 32768
order by schema_name(t.schema_id), t.name, ix.name

    open CursorIndex
fetch next from CursorIndex into @SchemaName, @TableName, @IndexName, @FilterDefinition, @is_unique, @IndexTypeDesc, @IndexOptions, @is_disabled, @FileGroupName, @IsPrimaryXml, @PrimaryXmlIndexId, @PrimaryXmlIndexName, @XmlSecondaryTypeDesc

    while (@@fetch_status=0)
begin
 declare @IndexColumns varchar(max)
 declare @IncludedColumns varchar(max)
 
 set @IndexColumns=''
 set @IncludedColumns=''
 
 declare CursorIndexColumn cursor for
select col.name, ixc.is_descending_key, ixc.is_included_column
from sys.tables tb
         inner join sys.indexes ix on tb.object_id=ix.object_id
         inner join sys.index_columns ixc on ix.object_id=ixc.object_id and ix.index_id= ixc.index_id
         inner join sys.columns col on ixc.object_id =col.object_id  and ixc.column_id=col.column_id
where ix.type>0 and (ix.is_primary_key=0 or ix.is_unique_constraint=0)
  and schema_name(tb.schema_id)=@SchemaName and tb.name=@TableName and ix.name=@IndexName
order by ixc.index_column_id

    open CursorIndexColumn 
 fetch next from CursorIndexColumn into  @ColumnName, @IsDescendingKey, @IsIncludedColumn

    while (@@fetch_status=0)
begin

  if @IsIncludedColumn=0 
   set @IndexColumns=@IndexColumns + '[' + @ColumnName + ']'  + case when @IsDescendingKey=1 AND @IsPrimaryXml IS NULL then ' DESC, ' else case when @IsPrimaryXml IS NULL then  ' ASC, ' else ', ' end end
  else 
   set @IncludedColumns=@IncludedColumns + '[' + @ColumnName + '], ' 

  if @IndexTypeDesc = 'NONCLUSTERED COLUMNSTORE'
   set @IndexColumns=@IndexColumns + @ColumnName + ', '

  fetch next from CursorIndexColumn into @ColumnName, @IsDescendingKey, @IsIncludedColumn
end

close CursorIndexColumn
    deallocate CursorIndexColumn

 set @IndexColumns = IIF(LEN(@IndexColumns) > 1, substring(@IndexColumns, 1, len(@IndexColumns)-1), '')
 set @IncludedColumns = case when len(@IncludedColumns) >0 then substring(@IncludedColumns, 1, len(@IncludedColumns)-1) else '' end

 set @TSQLScripCreationIndex =''
 set @TSQLScripDisableIndex =''
 set @TSQLScripCreationIndex='CREATE '+ @is_unique  +@IndexTypeDesc + ' INDEX ' +QUOTENAME(@IndexName)+' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName)+ IIF(LEN(@IndexColumns) > 1, ' ('+@IndexColumns+') ', '')+ 
  case when len(@IncludedColumns)>0 then CHAR(13) +'INCLUDE (' + @IncludedColumns+ ')' else '' end + CHAR(13) + 
  case when @PrimaryXmlIndexName IS NOT NULL then 'USING XML INDEX [' + @PrimaryXmlIndexName + '] FOR ' + @XmlSecondaryTypeDesc + ' ' else '' end + 
  case when len(@FilterDefinition)>0 then CHAR(13) +'WHERE ' + @FilterDefinition else '' end + CHAR(13) + 
  'WITH (' + @IndexOptions+ ')' + case when @IsPrimaryXml IS NULL then ' ON ' + QUOTENAME(@FileGroupName) + ';' else ';' end

 if @is_disabled=1 
  set  @TSQLScripDisableIndex=  CHAR(13) +'ALTER INDEX ' +QUOTENAME(@IndexName) + ' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName) + ' DISABLE;' + CHAR(13) 

if @IndexTypeDesc = 'CLUSTERED COLUMNSTORE' begin
    set @TSQLScripCreationIndex='CREATE '+ @is_unique + 'CLUSTERED COLUMNSTORE INDEX ' +QUOTENAME(@IndexName)+' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName) +
    case when len(@FilterDefinition)>0 then CHAR(13) +'WHERE ' + @FilterDefinition else '' end + CHAR(13) + 
    ' WITH (' + @IndexOptions+ ') ON ' + QUOTENAME(@FileGroupName) + ';'
end

if @IndexTypeDesc = 'NONCLUSTERED COLUMNSTORE' begin
    set @TSQLScripCreationIndex='CREATE '+ @is_unique + 'NONCLUSTERED COLUMNSTORE INDEX ' +QUOTENAME(@IndexName)+' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName) + IIF(LEN(@IndexColumns) > 1, ' ('+@IndexColumns+')', '')+  +' WITH (' + @IndexOptions+ ') ON ' + QUOTENAME(@FileGroupName) + ';'
end

INSERT INTO #Results
([SCHEMA_NAME], [TABLE_NAME], [IndexName], [CreateIndex], [IsPrimaryXml], [PrimaryXmlIndexId], [PrimaryXmlIndexName], [XmlSecondaryTypeDesc])
VALUES
    (@SchemaName, @TableName, @IndexName, @TSQLScripCreationIndex + CHAR(13) + CHAR(10) + @TSQLScripDisableIndex + CHAR(13) + CHAR(10) + 'GO -- SQRIBE/GO' + CHAR(13) + CHAR(10), @IsPrimaryXml, @PrimaryXmlIndexId, @PrimaryXmlIndexName, @XmlSecondaryTypeDesc)

    fetch next from CursorIndex into  @SchemaName, @TableName, @IndexName, @FilterDefinition, @is_unique, @IndexTypeDesc, @IndexOptions, @is_disabled, @FileGroupName, @IsPrimaryXml, @PrimaryXmlIndexId, @PrimaryXmlIndexName, @XmlSecondaryTypeDesc
end


-- VIEWS

declare CursorIndex2 cursor for
select schema_name(t.schema_id) [schema_name], t.name, ix.name, ix.filter_definition,
        case when xi.xml_index_type IS NULL AND ix.is_unique = 1 then 'UNIQUE ' else '' END +
        case when xi.xml_index_type = 0 then 'PRIMARY ' else '' END
     , ix.type_desc, '' +
                     CASE when ix.type_desc LIKE '%CLUSTERED COLUMNSTORE' THEN
                                  'COMPRESSION_DELAY=' + CAST(ix.compression_delay AS varchar(255))
                          ELSE
                                  case when ix.is_padded=1 then 'PAD_INDEX=ON, ' else 'PAD_INDEX=OFF, ' end
                                  + case when ix.allow_page_locks=1 then 'ALLOW_PAGE_LOCKS=ON, ' else 'ALLOW_PAGE_LOCKS=OFF, ' end
                                  + case when ix.allow_row_locks=1 then  'ALLOW_ROW_LOCKS=ON, ' else 'ALLOW_ROW_LOCKS=OFF, ' end
                                  + case when INDEXPROPERTY(t.object_id, ix.name, 'IsStatistics') = 1 then 'STATISTICS_NORECOMPUTE=ON, ' else 'STATISTICS_NORECOMPUTE=OFF, ' end
                                  + case when ix.ignore_dup_key=1 then 'IGNORE_DUP_KEY=ON, ' else 'IGNORE_DUP_KEY=OFF, ' end
                                  + case when ix.compression_delay is not null then ('COMPRESSION_DELAY=' + CAST(ix.compression_delay AS varchar(255)) + ', ') else '' end
                                  + 'SORT_IN_TEMPDB=OFF, FILLFACTOR=' + CONVERT(VARCHAR(5), CASE WHEN ix.fill_factor = 0 THEN 100 ELSE ix.fill_factor END)
                         END AS IndexOptions
     , ix.is_disabled , FILEGROUP_NAME(ix.data_space_id) FileGroupName, xi.xml_index_type, xi.using_xml_index_id, xi2.name, xi.secondary_type_desc
from sys.views t
         inner join sys.indexes ix on t.object_id=ix.object_id
         left join sys.xml_indexes xi on xi.name=ix.name
         left join sys.xml_indexes xi2 on xi2.index_id=xi.using_xml_index_id and xi2.object_id=xi.object_id
where ix.type>0 and ix.is_primary_key=0 and ix.is_unique_constraint=0 --and schema_name(tb.schema_id)= @SchemaName and tb.name=@TableName
  and t.is_ms_shipped=0 and t.name<>'sysdiagrams'
order by schema_name(t.schema_id), t.name, ix.name

    open CursorIndex2
fetch next from CursorIndex2 into @SchemaName, @TableName, @IndexName, @FilterDefinition, @is_unique, @IndexTypeDesc, @IndexOptions,@is_disabled, @FileGroupName, @IsPrimaryXml, @PrimaryXmlIndexId, @PrimaryXmlIndexName, @XmlSecondaryTypeDesc

    while (@@fetch_status=0)
begin
 
 set @IndexColumns=''
 set @IncludedColumns=''
 
 declare CursorIndex2Column cursor for
select col.name, ixc.is_descending_key, ixc.is_included_column
from sys.views tb
         inner join sys.indexes ix on tb.object_id=ix.object_id
         inner join sys.index_columns ixc on ix.object_id=ixc.object_id and ix.index_id= ixc.index_id
         inner join sys.columns col on ixc.object_id =col.object_id  and ixc.column_id=col.column_id
where ix.type>0 and (ix.is_primary_key=0 or ix.is_unique_constraint=0)
  and schema_name(tb.schema_id)=@SchemaName and tb.name=@TableName and ix.name=@IndexName
order by ixc.index_column_id

    open CursorIndex2Column 
 fetch next from CursorIndex2Column into  @ColumnName, @IsDescendingKey, @IsIncludedColumn

    while (@@fetch_status=0)
begin

  if @IsIncludedColumn=0 
   set @IndexColumns=@IndexColumns + '[' + @ColumnName + ']'  + case when @IsDescendingKey=1 AND @IsPrimaryXml IS NULL then ' DESC, ' else case when @IsPrimaryXml IS NULL then  ' ASC, ' else ', ' end end
  else 
   set @IncludedColumns=@IncludedColumns + '[' + @ColumnName + '], ' 

  if @IndexTypeDesc = 'NONCLUSTERED COLUMNSTORE'
   set @IndexColumns=@IndexColumns + @ColumnName + ', '

  fetch next from CursorIndex2Column into @ColumnName, @IsDescendingKey, @IsIncludedColumn
end

close CursorIndex2Column
    deallocate CursorIndex2Column

 set @IndexColumns = IIF(LEN(@IndexColumns) > 1, substring(@IndexColumns, 1, len(@IndexColumns)-1), '')
 set @IncludedColumns = case when len(@IncludedColumns) >0 then substring(@IncludedColumns, 1, len(@IncludedColumns)-1) else '' end

 set @TSQLScripCreationIndex =''
 set @TSQLScripDisableIndex =''
 set @TSQLScripCreationIndex='CREATE '+ @is_unique  +@IndexTypeDesc + ' INDEX ' +QUOTENAME(@IndexName)+' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName)+ IIF(LEN(@IndexColumns) > 1, ' ('+@IndexColumns+') ', '')+ 
  case when len(@IncludedColumns)>0 then CHAR(13) +'INCLUDE (' + @IncludedColumns+ ')' else '' end + CHAR(13) + 
  case when @PrimaryXmlIndexName IS NOT NULL then 'USING XML INDEX [' + @PrimaryXmlIndexName + '] FOR ' + @XmlSecondaryTypeDesc + ' ' else '' end + 
  case when len(@FilterDefinition)>0 then CHAR(13) +'WHERE ' + @FilterDefinition else '' end + CHAR(13) + 
  'WITH (' + @IndexOptions+ ')' + case when @IsPrimaryXml IS NULL then ' ON ' + QUOTENAME(@FileGroupName) + ';' else ';' end

 if @is_disabled=1 
  set  @TSQLScripDisableIndex=  CHAR(13) +'ALTER INDEX ' +QUOTENAME(@IndexName) + ' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName) + ' DISABLE;' + CHAR(13) 

if @IndexTypeDesc = 'CLUSTERED COLUMNSTORE' begin
    set @TSQLScripCreationIndex='CREATE '+ @is_unique + 'CLUSTERED COLUMNSTORE INDEX ' +QUOTENAME(@IndexName)+' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName) +
    case when len(@FilterDefinition)>0 then CHAR(13) +'WHERE ' + @FilterDefinition else '' end + CHAR(13) + 
    ' WITH (' + @IndexOptions+ ') ON ' + QUOTENAME(@FileGroupName) + ';'
end

if @IndexTypeDesc = 'NONCLUSTERED COLUMNSTORE' begin
    set @TSQLScripCreationIndex='CREATE '+ @is_unique + 'NONCLUSTERED COLUMNSTORE INDEX ' +QUOTENAME(@IndexName)+' ON ' + QUOTENAME(@SchemaName) +'.'+ QUOTENAME(@TableName) + IIF(LEN(@IndexColumns) > 1, ' ('+@IndexColumns+')', '')+ 
    case when len(@FilterDefinition)>0 then CHAR(13) +'WHERE ' + @FilterDefinition else '' end + CHAR(13) + 
    ' WITH (' + @IndexOptions+ ') ON ' + QUOTENAME(@FileGroupName) + ';'
end

INSERT INTO #Results
([SCHEMA_NAME], [TABLE_NAME], [IndexName], [CreateIndex], [IsPrimaryXml], [PrimaryXmlIndexId], [PrimaryXmlIndexName], [XmlSecondaryTypeDesc])
VALUES
    (@SchemaName, @TableName, @IndexName, @TSQLScripCreationIndex + CHAR(13) + CHAR(10) + @TSQLScripDisableIndex + CHAR(13) + CHAR(10) + 'GO -- SQRIBE/GO' + CHAR(13) + CHAR(10), @IsPrimaryXml, @PrimaryXmlIndexId, @PrimaryXmlIndexName, @XmlSecondaryTypeDesc)

    fetch next from CursorIndex2 into  @SchemaName, @TableName, @IndexName, @is_unique, @IndexTypeDesc, @IndexOptions,@is_disabled, @FileGroupName, @IsPrimaryXml, @PrimaryXmlIndexId, @PrimaryXmlIndexName, @XmlSecondaryTypeDesc

end

close CursorIndex
    deallocate CursorIndex

close CursorIndex2
    deallocate CursorIndex2

SELECT * FROM #Results
DROP TABLE #Results
