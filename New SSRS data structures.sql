/*
Purpose:
Author: Hans Aisake
Date Created: July 14, 2020
Comments:
-- I think the way the indicators are decoded needs to be put into view.
-- The YOY version may also be better situated in a view.
-- I think the view was the original plan but somehow I strayed

*/

	Declare @productname varchar(255) = 'Richmond True North Scorecard'

	---------------------------
	-- Build DSSI.dbo.TRUE_NORTH_INDICATORS_YOY
	---------------------------
	/* pull the indicator data in long form */
	IF OBJECT_ID('tempdb.dbo.#stage') is not null DROP TABLE #stage;

	SELECT 
	ISNULL(PID.IndicatorDisplayID, IND.IndicatorID) as 'IndicatorID'
	, P.ProductName															/* formerly facility */
	, H.EntityName as 'Parent'												/* formerly like program */
	, ISNULL(PE.[EntityLongNameOverride], ENT.EntityName ) as 'EntityName'	/* formerly program */
	, T.EndDateTime as 'TimeFrame'
	, T.[Label] as 'TimeFrameLabel'
	, T.[Type] as 'TimeFrameType'
	, ISNULL(PID.IndicatorLongNameOverride, IND.IndicatorLongName) as 'IndicatorName'
	, 'TEMP' as 'IndicatorCategory'
	, VAL.Numerator
	, VAL.Denominator
	, VAL.[Result]	/* formerly Value */
	, VAL.[Target]
	, PID.[DesiredDirection]
	, PID.[TextPrecision]	/* formerly like format */
	, PID.[ChartPrecision]	/* formerly like format */
	, VAL.DataSource
	, CASE WHEN ENT.EntityName in ('Richmond Hospial TNS', 'Vancouver Acute TNS') THEN 1 ELSE 0 END as 'IsOverall'
	/*, PID.IndicatorCategory -- we didn't make a feaure to support this label */
	, PID.Textunits		/*formerly like units */
	, PID.ChartUnits	/*formerly like units */
	/*, PE.Hide_Entity    --formerly Hide_Chart	; we haven't sorted out this feature yet */
	,CASE WHEN LEFT(PID.Textunits,1)='%' AND PID.TextPrecision =0 THEN '0%'
		  WHEN LEFT(PID.TextUnits,1)='%' AND PID.TextPrecision =1 THEN '0.0%'
		  WHEN LEFT(PID.TextUnits,1)='%' AND PID.TextPrecision =2 THEN '0.00%'
		  WHEN LEFT(PID.TextUnits,1)='%' AND PID.TextPrecision >=3 THEN '0.000%'
		  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision =0 THEN '0'
		  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision =1 THEN '0.0'
		  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision =2 THEN '0.00'
		  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision >=3 THEN '0.000'
		  ELSE '0'
	END as 'SSRS_TextFormat'
	INTO #stage
	FROM DSSI.dbo.AISAKE_BSI_indicatorValues as VAL
	INNER JOIN DSSI.dbo.AISAKE_BSI_Indicator as IND
	ON VAL.IndicatorID= IND.IndicatorID
	INNER JOIN DSSI.dbo.AISAKE_BSI_TimeFrame as T
	ON VAL.TimeFrameID=T.TimeFrameID
	INNER JOIN DSSI.dbo.AISAKE_BSI_Entity as ENT
	ON VAL.EntityID=ENT.EntityID
	INNER JOIN DSSI.dbo.AISAKE_BSI_Product as P
	ON P.ProductName = @productname  /* in (  'Richmond True North Scorecard', 'Vancouver True North Scorecard')*/
	INNER JOIN DSSI.dbo.AISAKE_BSI_ProductEntity as PE
	ON PE.EntityID=VAL.EntityID
	AND PE.ProductID=P.ProductID
	INNER JOIN DSSI.dbo.AISAKE_BSI_IndicatorProduct as PID
	ON VAL.IndicatorID=PID.IndicatorID
	AND PID.ProductID =P.ProductID
	LEFT JOIN DSSI.dbo.AISAKE_BSI_EntityHeirarchy as H
	ON VAL.EntityID = H.EntityChildID
	;
	
	-- Convert the data into a YOY format
	ALTER TABLE #stage
	ADD TimeFrameYear varchar(4)
	, TimeFrameUnit varchar(10)
	;
	GO

	--add columns to hold YOY columns
	UPDATE #stage
	SET TimeFrameYear = CASE WHEN timeFrameType='FiscalPeriod'  THEN LEFT(TimeFrameLabel,4)  
--							 WHEN timeFrameType='FiscalQuarter' THEN LEFT(TimeFrameLabel,4)
--							 WHEN timeFrameType='FQHH'  THEN LEFT(TimeFrameLabel,4)  
							 ELSE 1900
						END
	, TimeFrameUnit = CASE WHEN timeFrameType='FiscalPeriod'  THEN 'P'+RIGHT(TimeFrameLabel,2)  
--						   WHEN timeFrameType='FiscalQuarter' THEN 'FQ'+RIGHT(TimeFrameLabel,2) 
--						   WHEN timeFrameType='FQHH' THEN 'FQ'+RIGHT(TimeFrameLabel,2) 
						   ELSE 'U'
					  END
	;
	GO

	--manipulate the structure into an excel like structure
	IF OBJECT_ID('tempdb.dbo.#skeleton') is not null DROP TABLE #skeleton;
	GO

	SELECT X.*, Y.TimeFrameUnit
	INTO #skeleton 
	FROM
	(
		SELECT distinct IndicatorID, IndicatorName, ProductName, Parent, EntityName, DataSource, [TimeFrameType], DesiredDirection
		, CAST(MAX(TimeFrameYear) as int) as 'LatestYear'
		, MAX(TimeFrameYear) -1  as 'LastYear'
		, MAX(TimeFrameYear) -2  as 'TwoYearsAgo'
		, CAST( MAX(TimeFrameYear)-1 as varchar(9) ) +'/' + CAST( MAX(TimeFrameYear) as varchar(9))  as 'LatestYearLabel'
		, CAST( MAX(TimeFrameYear)-2 as varchar(9) ) +'/' + CAST( MAX(TimeFrameYear)-1 as varchar(9))  as 'LastYearLabel'
		, CAST( MAX(TimeFrameYear)-3 as varchar(9) ) +'/' + CAST( MAX(TimeFrameYear)-2 as varchar(9))  as 'TwoYearsAgoLabel'
		, ChartUnits
		, ChartPrecision
		, Textunits
		, TextPrecision
		, SSRS_TextFormat
		, IsOverall
		FROM #stage
		WHERE 	EntityName not in ('Allied Health Practice Leads'
,'BISS'
,'Cardiology'
,'Comm Geriatrics & Spiritual Cr'
,'Flow & Acute Tower Redev'
,'Health Protection'
,'Medical Admin'
,'Non Corporate Unallocated'
,'Palliative'
,'Plastic Surgery'
,'Psychiatry'
,'Regional Clinical Services'
,'Regional Unallocated-RHS'
,'RH Unallocated'
,'RHS Central Recoveries'
,'SDCO'
,'System Improvement'
,'Volunteers')

		GROUP BY IndicatorID, IndicatorName, ProductName, Parent, EntityName, DataSource, [TimeFrameType], DesiredDirection, ChartUnits, ChartPrecision, Textunits, TextPrecision, SSRS_TextFormat, IsOverall
	) as X
	LEFT JOIN
	(
		SELECT distinct IndicatorID, TimeFrameUnit 
		FROM #stage
	) as Y
	ON X.IndicatorID=Y.IndicatorID
	;
	GO

	--manipulate the structure into an excel like structure 
	IF OBJECT_ID('tempdb.dbo.#YOY_stage') is not null DROP TABLE #YOY_stage;
	GO

	SELECT P.IndicatorID
	, Cast( P.IndicatorName as varchar(255)) as 'IndicatorName'
	, P.ProductName
	, P.Parent
	, P.EntityName
	, CAST( P.DataSource as varchar(255)) as 'DataSource'
	, P.[TimeFrameType]
	, P.DesiredDirection
	, P.TimeFrameUnit
	, P.LatestYear
	, P.LastYear
	, P.TwoYearsAgo
	, P.LatestYearLabel
	, P.LastYearLabel
	, P.TwoYearsAgoLabel
	, X.[Target]
	, X.[Result] as 'LatestYear_Value'
	, Y.[Result] as 'LastYear_Value'
	, Z.[Result] as 'TwoYearsAgo_Value'
	, P.ChartPrecision
	, P.ChartUnits
	, P.TextPrecision
	, P.Textunits
	, P.SSRS_TextFormat
	, P.IsOverall
	INTO #YOY_stage
	FROM #skeleton as P
	LEFT JOIN #stage as X	--get latest year value
	ON P.IndicatorID = X.IndicatorID 
	AND P.ProductName = X.ProductName
	AND P.Parent  = X.Parent
	AND P.EntityName = X.EntityName
	AND P.LatestYear  = X.TimeFrameYear 
	AND P.TimeFrameUnit = X.TimeFrameUnit

	LEFT JOIN #stage as Y	--get latest year value
	ON P.IndicatorID = Y.IndicatorID 
	AND P.ProductName = Y.ProductName
	AND P.Parent  = Y.Parent
	AND P.EntityName = Y.EntityName
	AND P.LatestYear  = Y.TimeFrameYear 
	AND P.TimeFrameUnit = Y.TimeFrameUnit

	LEFT JOIN #stage as Z	--get latest year value
	ON P.IndicatorID = Z.IndicatorID 
	AND P.ProductName = Z.ProductName
	AND P.Parent  = Z.Parent
	AND P.EntityName = Z.EntityName
	AND P.LatestYear  = Z.TimeFrameYear 
	AND P.TimeFrameUnit = Z.TimeFrameUnit

	--WHERE X.[Value] is not null OR Y.[Value] is not null OR Z.[Value] is not null
	;
	GO

	--fill in the target series for the current year
	UPDATE X 
	SET [Target]=Y.[Target]
	FROM #YOY_stage as X
	LEFT JOIN ( 
		SELECT distinct IndicatorID, ProductName, Parent, EntityName, [Target] 
		FROM #YOY_stage 
		WHERE [Target] is not null
	) as Y
	ON X.IndicatorID = Y.IndicatorID 
	AND X.ProductName = Y.ProductName
	AND X.Parent  = Y.Parent
	AND X.EntityName = Y.EntityName
	WHERE X.[Target] is null
	;
	GO

	----save the results to the YOY table
	TRUNCATE TABLE DSSI.[dbo].[TRUE_NORTH_INDICATORS_YOY]
	GO

	INSERT INTO DSSI.[dbo].[TRUE_NORTH_INDICATORS_YOY]
	([IndicatorID] ,[IndicatorName] ,[ProductName]
      ,[Parent] ,[EntityName] ,[DataSource], [TimeFrameType] ,[DesiredDirection]
      ,[TimeFrameUnit] ,[LatestYear], [LastYear] ,[TwoYearsAgo]
      ,[LatestYearLabel], [LastYearLabel], [TwoYearsAgoLabel]
      ,[Target],[LatestYear_Value], [LastYear_Value]
      ,[TwoYearsAgo_Value], [ChartPrecision], [ChartUnits]
      ,[TextPrecision], [Textunits], SSRS_FormatText, ISOverall
	  )
	SELECT * 
	FROM #YOY_stage 
	;
	GO

	--------------------------
	-- MasterTableAll
	--------------------------
	SELECT * 
FROM DSSI.[dbo].[TRUE_NORTH_INDICATORS_YOY]
WHERE productname = @productname



	-------------------------
	-- for most recent - combine with #stage
	-------------------------

/* pull the indicator data in long form */
IF OBJECT_ID('tempdb.dbo.#stage') is not null DROP TABLE #stage;

SELECT ISNULL(PID.IndicatorDisplayID, IND.IndicatorID) as 'IndicatorID'
, P.ProductName								
, H.EntityName as 'Parent'							
, ISNULL(PE.[EntityLongNameOverride], ENT.EntityName ) as 'EntityName'	
, T.EndDateTime as 'TimeFrame'
, T.[Label] as 'TimeFrameLabel'
, T.[Type] as 'TimeFrameType'
, ISNULL(PID.IndicatorLongNameOverride, IND.IndicatorLongName) as 'IndicatorName'
, 'TEMP' as 'IndicatorCategory'
, VAL.Numerator
, VAL.Denominator
, VAL.[Result]	/* formerly Value */
, VAL.[Target]
, PID.[DesiredDirection]
, PID.[TextPrecision]	/* formerly like format */
, PID.[ChartPrecision]	/* formerly like format */
, VAL.DataSource
, CASE WHEN ENT.EntityName in ('Richmond Hospial TNS', 'Vancouver Acute TNS') THEN 1 ELSE 0 END as 'IsOverall'
, PID.Textunits		/*formerly like units */
, PID.ChartUnits	/*formerly like units */
,CASE WHEN LEFT(PID.Textunits,1)='%' AND PID.TextPrecision =0 THEN '0%'
	  WHEN LEFT(PID.TextUnits,1)='%' AND PID.TextPrecision =1 THEN '0.0%'
	  WHEN LEFT(PID.TextUnits,1)='%' AND PID.TextPrecision =2 THEN '0.00%'
	  WHEN LEFT(PID.TextUnits,1)='%' AND PID.TextPrecision >=3 THEN '0.000%'
	  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision =0 THEN '0'
	  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision =1 THEN '0.0'
	  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision =2 THEN '0.00'
	  WHEN LEFT(PID.TextUnits,1)!='%' AND PID.TextPrecision >=3 THEN '0.000'
	  ELSE '0'
END as 'SSRS_TextFormat'
INTO #stage
FROM DSSI.dbo.AISAKE_BSI_indicatorValues as VAL
INNER JOIN DSSI.dbo.AISAKE_BSI_Indicator as IND
ON VAL.IndicatorID= IND.IndicatorID
INNER JOIN DSSI.dbo.AISAKE_BSI_TimeFrame as T
ON VAL.TimeFrameID=T.TimeFrameID
INNER JOIN DSSI.dbo.AISAKE_BSI_Entity as ENT
ON VAL.EntityID=ENT.EntityID
INNER JOIN DSSI.dbo.AISAKE_BSI_Product as P
ON P.ProductName = @productname 
INNER JOIN DSSI.dbo.AISAKE_BSI_ProductEntity as PE
ON PE.EntityID=VAL.EntityID
AND PE.ProductID=P.ProductID
INNER JOIN DSSI.dbo.AISAKE_BSI_IndicatorProduct as PID
ON VAL.IndicatorID=PID.IndicatorID
AND PID.ProductID =P.ProductID
LEFT JOIN DSSI.dbo.AISAKE_BSI_EntityHeirarchy as H
ON VAL.EntityID = H.EntityChildID
;

/* Identify latest timeframe by indicator */
IF OBJECT_ID('tempdb.dbo.#latestTF') is not null DROP TABLE #latestTF;

SELECT distinct IndicatorName
, Parent
, MAX(timeframe) as 'LatestTimeFrame'
INTO #latestTF
FROM #stage
GROUP BY IndicatorName
, Parent
;

/* pull most recent indicator rows */
IF OBJECT_ID('tempdb.dbo.#mostRecent') is not null DROP TABLE #mostRecent;

SELECT distinct X.*
INTO #mostRecent
FROM #stage as X
INNER JOIN #latestTF as Y
ON  X.TimeFrame=Y.LatestTimeFrame
AND X.Parent=Y.Parent
AND X.IndicatorName=Y.IndicatorName
WHERE X.EntityName not in ('Allied Health Practice Leads'
,'BISS'
,'Cardiology'
,'Comm Geriatrics & Spiritual Cr'
,'Flow & Acute Tower Redev'
,'Health Protection'
,'Medical Admin'
,'Non Corporate Unallocated'
,'Palliative'
,'Plastic Surgery'
,'Psychiatry'
,'Regional Clinical Services'
,'Regional Unallocated-RHS'
,'RH Unallocated'
,'RHS Central Recoveries'
,'SDCO'
,'System Improvement'
,'Volunteers')
;

SELECT * FROM #mostRecent
	
	------------------------
	-- EntityList
	------------------------
	SELECT distinct EntityName
FROM DSSI.dbo.TRUE_NORTH_INDICATORS_YOY
WHERE ProductName = @productname
AND EntityName not in ('Allied Health Practice Leads'
,'BISS'
,'Cardiology'
,'Comm Geriatrics & Spiritual Cr'
,'Flow & Acute Tower Redev'
,'Health Protection'
,'Medical Admin'
,'Non Corporate Unallocated'
,'Palliative'
,'Plastic Surgery'
,'Psychiatry'
,'Regional Clinical Services'
,'Regional Unallocated-RHS'
,'RH Unallocated'
,'RHS Central Recoveries'
,'SDCO'
,'System Improvement'
,'Volunteers')
;

	-------------------------
	-- for sparkline chart
	-------------------------

	SELECT * FROM #stage


	SELECT * 
	FROM DSSI.[dbo].[TRUE_NORTH_INDICATORS_YOY]
	WHERE ProductName = @productname