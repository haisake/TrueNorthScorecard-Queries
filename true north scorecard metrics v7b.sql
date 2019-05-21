/*
Purpose: To create a consolidated query that constructs the indciators for the true north richmond scorecard
Author: Hans Aisake
Date Created: April 1, 2019
Date Modified: April 29, 2019
Inclusions/Exclusions:
Comments:
*/ 

------------------------
--Indentify true inpatient units
------------------------
	--I'm not sure if this is up to date anymore
	--Flora mentioned building a maping table somewhere
	IF OBJECT_ID('tempdb.dbo.#adtcNUClassification_tnr') IS NOT NULL DROP TABLE #adtcNUClassification_tnr;

	SELECT f.[FacilityCode]
	, f.[FacilityShortName]
	, f.[FacilityLongName]
	, f.[Site]
	, n.NursingUnit as NursingUnitCode
	, NULevel = 'Acute'
	INTO #adtcNUClassification_tnr
	FROM [ADTCMart].[dim].[NursingUnit] n
	LEFT JOIN [ADTCMart].[dim].[Facility] f on n.facilityID = f.facilityID
	WHERE f.[FacilityCode] in ('0001', '0002', '0007', '0112', 'PR', 'SM', 'SG', 'SPH', 'MSJ'); -- 9 regional acute hospitals
	GO

	ALTER TABLE #adtcNUClassification_tnr
	ALTER COLUMN NULevel varchar(50) not null;
	GO

	UPDATE #adtcNUClassification_tnr
	SET NULevel = 'Extended Care'
	WHERE FacilityShortName in ('VGH', 'UBCH', 'RHS', 'LGH', 'MSJ', 'SGH', 'PRGH')
	AND NursingUnitCode in ('BP2E', 'BP2W', 'BP3E', 'BP3W', 'BP4E', 'BP4W', 'UP1E', 'UP1W', 'UP2E', 'UP2W', 'UP3E', 'UP3W', 'UP4E', 'UP4W', 'M1E', 'M1W', 'M2E', 'M2W', 'M3W', 'EN1', 'EN2', 'ES1', 'ES2', 'ES3', 'M2W', 'MEC2', 'H1N', 'H1S', 'H2N', 'H2S', 'HSU', 'HTN','NSH SSH', 'BF3', 'BF4', 'HEC1', 'HEC2', 'HEC3', 'LASP', 'LBIR', 'LCDR', 'YOU2', 'YOU3', 'EEVF', 'TOTEM', 'POD', 'GW2', 'GW3', 'GW4','GW5', 'GW6', 'SHOR', 'YRS')	--some could argue this isn't extended care but rather a stepdown unit
	;
	GO

	UPDATE #adtcNUClassification_tnr
	SET NULevel ='Hospice'
	WHERE /*FacilityShortName in ('VGH', 'UBCH', 'RHS', 'LGH', 'MSJ', 'SGH')
	AND*/ NursingunitCode in ('NSH', 'PSJH')
	;
	GO

	UPDATE #adtcNUClassification_tnr
	SET NULevel = 'Day Care'
	WHERE FacilityShortName in ('VGH', 'RHS', 'LGH', 'MSJ', 'SPH', 'PRGH')
	AND NursingUnitCode in ('MDC', 'RSDC', 'DCM', 'DCP', 'DCR', 'DCS', 'PDC/INPT', 'SDC', 'MSDC');
	GO

	UPDATE #adtcNUClassification_tnr
	SET NULevel = 'Transitional Care'
	WHERE FacilityShortName in ('UBCH', 'LGH')
	AND NursingUnitCode in ('UK1T', 'UK2C', 'A2T', 'TCU');
	GO

	UPDATE #adtcNUClassification_tnr
	SET NULevel = 'Tertiary MH'
	WHERE FacilityShortName in ('UBCH', 'VGH'/*, 'LRH', 'YRH'*/)
	AND NursingUnitCode in ('WCC2', 'WP2', 'WP3', 'WP4', 'WP5', 'WP6', 'UD1W', 'UD2S', 'UD2T', 'YOU4', 'YOU5', 'LALT', 'S4MH');
	GO

	UPDATE #adtcNUClassification_tnr
	SET NULevel = 'Geriatric Care'
	WHERE FacilityShortName in ('VGH')
	AND NursingUnitCode in ('C5A','L5A')
	;
	GO

-----------------------------------------------
--Reporting TimeFrames
-----------------------------------------------

	--reporting periods, based on 1 day lag
	IF OBJECT_ID('tempdb.dbo.#TNR_FPReportTF') IS NOT NULL DROP TABLE #TNR_FPReportTF;
	GO

	SELECT distinct TOP 39 FiscalPeriodLong, fiscalperiodstartdate, fiscalperiodenddate, FiscalPeriodEndDateID, FiscalPeriod, FiscalYearLong
	INTO #TNR_FPReportTF
	FROM ADTCMart.dim.[Date]
	WHERE fiscalperiodenddate <= DATEADD(day, -1, GETDATE())
	ORDER BY FiscalPeriodEndDate DESC
	;
	GO
	
---------------------------------------------------
--Finance Data from the General Ledger - April 2019
---------------------------------------------------
	
	-------------------
	-- Inpatient Days
	-------------------
		--we mostly need an inpatient days definition for indicators 6, 12, 14, and the ALOS
		--different sources are used for all these indicators with different criteria for different reports, which is a load of crap.
		--I'm syncronizing this report to a single inpatient days number for each period
		--what mapping we use can change as we go, but here I get everything by cost center

		--gets the inpatient days from financemart the same was as for HPPD; uses the default program mapping in financemart
		IF OBJECT_ID('tempdb.dbo.#tnr_inpatientDaysByCC') is not null DROP TABLE #tnr_inpatientDaysByCC;
		GO

		SELECT D.FiscalYearLong, D.FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodStartDate, D.FiscalPeriodEndDate,  cc.CostCenterCode, ledger.FinSiteID, P.EntityDesc
		, ISNULL(sum(ledger.BudgetAmt), 0.00) as 'BudgetedCensusDays'
		, ISNULL(sum(ledger.ActualAmt),0.00) as 'ActualCensusDays'
		INTO #tnr_inpatientDaysByCC
		FROM FinanceMart.Finance.GLAccountStatsFact as ledger
		LEFT JOIN FinanceMart.dim.CostCenter as CC
		ON ledger.CostCenterID=CC.CostCenterID
		LEFT JOIN FinanceMart.finance.EntityProgramSubProgram as P		--get the entity of the cost center fin site id
		ON ledger.[CostCenterBusinessUnitEntitySiteID]=P.[CostCenterBusinessUnitEntitySiteID]
		INNER JOIN #TNR_FPReportTF as D					--only fiscal year/period we want to report on as defined in #hppd_fp
		ON ledger.FiscalPeriodEndDateID=d.FiscalPeriodEndDateID	--same fiscal period and year
		WHERE (ledger.GLAccountCode like '%S403%')	--S403 is all inpatient day accounts this includes the new born accounts. S404 is for residential care days and used in the BSc, but it doens't catch any thing.
		GROUP BY D.FiscalYearLong, D.FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodStartDate, D.FiscalPeriodEndDate,  cc.CostCenterCode, ledger.FinSiteID, P.EntityDesc
		GO

	-------------------
	-- Productive Hours by program based on the BSC query for HPPD; Might want to double check this
	-------------------
		IF OBJECT_ID('tempdb.dbo.#tnr_relevantCC') is not null DROP TABLE #tnr_relevantCC;
		GO

		 WITH costCenterList AS (
			--CTE anchor member
			SELECT CiHiMISGroupingID, CiHiMISGroupingDESC, Cihimisgroupingcode , CostCenterID 
			FROM FinanceMart.Dim.CiHiMISGrouping
			WHERE Cihimisgroupingcode in ('71210','71220','71230','71240','71250','71270','71275','71280','7131040','71290')	--high level cost center parent groups to include for productive hours inclusion
			UNION all
			--recursively look up children cost centers till none are found
			SELECT c.CiHiMISGroupingID, C.CiHiMISGroupingDESC, c.Cihimisgroupingcode , c.CostCenterID
			FROM FinanceMart.Dim.CiHiMISGrouping C 
			INNER JOIN costCenterList ON C.ParentCiHiMISGroupingID=costCenterList.CiHiMISGroupingID
			WHERE c.CiHiMISGroupingID != c.ParentCiHiMISGroupingID
		)

		--save the CTE into a temp table; used a productive horus filter
		SELECT costCenterList.Cihimisgroupingcode, costCenterList.CiHiMISGroupingDESC, cc.* 
		INTO #tnr_relevantCC 
		FROM costCenterList 
		INNER JOIN FinanceMart.[Dim].[CostCenter] cc 
		ON costCenterList.CostCenterID=cc.CostCenterID 
		;
		GO

		--get productive hours
		IF OBJECT_ID('tempdb.dbo.#tnr_productiveHoursPRGM') is not null DROP TABLE #tnr_productiveHoursPRGM;
		GO

		SELECT [hours].FiscalYearLong, [hours].FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodEndDate, P.EntityDesc, P.ProgramDesc
		--, f.FinSiteCode, f.CostCenterCode
		--, cc.CostCenterDesc
		, SUM(ActualHrs) as 'ProdHrs' 
		, SUM(BudgetHrs) as 'BudgetHrs'
		INTO #tnr_productiveHoursPRGM
		FROM FinanceMart.Finance.LDProductiveHourByJobCategory as [hours]
		INNER JOIN #TNR_FPReportTF as D					--only fiscal year/period we want to report on
		ON [hours].FiscalYearLong=d.FiscalYearLong	--same fiscal year
		AND [hours].fiscalperiod =d.FiscalPeriod	--same fiscal period
		LEFT JOIN FinanceMart.finance.EntityProgramSubProgram as P		--get the entity of the cost center fin site id
		ON [hours].Costcenterid =P.CostCenterId and [hours].FinSiteId=P.FinSiteID
		WHERE --IsHPPDEligible=1 and 
		([hours].JobCategoryCode in ('RN','LPN','AIDE')	--only want these nursing hours as defined by opperations
		AND [hours].CostCenterCode in (Select CostCenterCode from #tnr_relevantCC)		--this is some klnd of elaborate way of filtering cost centers out based on CIHI groupings
		AND [hours].CostCenterCode NOT IN ('73402560', '72070031')				    --excluded for some additional reason
		AND [hours].costcentercode in (SELECT costcentercode FROM FinanceMart.[Dim].[CostCenter] WHERE SectorID IN (1,2)) -- 1-Acute, 2-Mental Health, 3-Other, 4-Residential, 5-TMH) --only include acute or mental health cost centers
		) OR [hours].CostCenterCode ='89905010'		--include this cost center for some reason
		GROUP BY [hours].FiscalYearLong, [hours].FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodEndDate, P.EntityDesc, P.ProgramDesc
		;
		GO
	------------------

---------------------------------------------------
--identify all possible indicator week combinations
---------------------------------------------------
	IF OBJECT_ID('tempdb.dbo.#placeholder') IS NOT NULL DROP TABLE #placeholder;
	GO

	SELECT * 
	INTO #placeholder
	FROM 
	(SELECT distinct FiscalPeriodLong as 'TimeFrameLabel', FiscalPeriodEndDate as 'timeFrame' , fiscalperiodstartdate FROM #TNR_FPReportTF) as X
	CROSS JOIN 
	(	SELECT distinct  Facility, indicatorId, indicatorname, program 
		FROM DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS]
		WHERE indicatorId in ('05','06','17') 
	) as Y
	;
	GO

	--find early cutoffs for the first of each indicator
	IF OBJECT_ID('tempdb.dbo.#cutoff') IS NOT NULL DROP TABLE #cutoff;
	GO

	SELECT program, indicatorid, [Facility], MIN([TimeFrameLabel]) as 'FirstTimeFrameLabel'
	INTO #cutoff
	FROM DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS] as Y
	GROUP BY program, indicatorid, [Facility]
	;
	GO

	--remove indicator rows that are too early
	DELETE X
	FROM #placeholder  as X 
	LEFT JOIN #cutoff as Y
	ON X.Program=Y.Program
	AND X.IndicatorID=Y.IndicatorID
	AND X.Facility=Y.Facility
	AND X.TimeFrameLabel>=Y.FirstTimeFrameLabel
	WHERE Y.IndicatorID is null 
	;
	GO

-----------------------------------------------
--ID 01 Percent of ED patients admitted to hospital within 10 hours - P4P
-----------------------------------------------
	/*
	Purpose: To compute how many people are admited into hospital FROM ED within 10 hrs of the decision to admit them.
	Author: Hans Aisake
	Date Created: April 1, 2019
	Date Updated: 
	Inclusions/Exclusions:
	Comments:
	*/

	--preprocess ED data and identify reporting time frames
	IF OBJECT_ID('tempdb.dbo.#tnr_ed01') IS NOT NULL DROP TABLE #tnr_ed01;
	GO

	--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
	SELECT 	T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, X.EDP_AdmitWithinTarget
	, X.Program
	, X.FacilityLongName
	INTO #TNR_ed01
	FROM
	(
		SELECT ED.StartDate
		, ED.EDP_AdmitWithinTarget
		, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
		, ED.FacilityLongName
		FROM EDMart.dbo.vwEDVisitIdentifiedRegional as ED
		LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--link to a fact table that identifies which program each unit goes to; not maintained by DMR
		ON ED.InpatientNursingUnitID= MAP.NursingUnitID			--same nursing unit id
		AND ED.StartDate BETWEEN MAP.StartDate AND MAP.EndDate	--within mapping dates; you could argue for inpatient date, but it's a minor issue
		WHERE ED.FacilityShortName='RHS'
		AND ED.admittedflag=1
		AND ED.StartDate >= (SELECT MIN(FiscalPeriodStartDate) FROM #TNR_FPReportTF)
		--AND IsNACRSSubmitted ='Y'	--this is not a well known filter but it only applies to about 1/1000 ed visits; this mostly delays initial reporting for several days and I've removed it. It seams to be non-value add
		AND not exists (SELECT 1 FROM EDMart.dbo.vwDTUDischargedHome as Z WHERE ED.continuumID=Z.ContinuumID)	--exclude clients discharged home from the DTU 
	) as X
	INNER JOIN #TNR_FPReportTF as T						--only keep reporting weeks we care about
	ON X.startdate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate
	;
	GO

	-----------------------------------------------
	--generate indicators and store the data
	-----------------------------------------------
	IF OBJECT_ID('tempdb.dbo.#TNR_ID01') IS NOT NULL DROP TABLE #TNR_ID01;
	GO

	SELECT 	'01' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Percent of ED Patients Admitted to Hospital Within 10 Hours' as 'IndicatorName'
	, sum(EDP_AdmitWithinTarget) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum(EDP_AdmitWithinTarget)/count(*) as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P0' as 'Format'
	,  CASE WHEN FiscalPeriodLong  <'2019-01' THEN 0.55
		    WHEN FiscalPeriodLong >='2019-01' THEN 0.58
	END as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	INTO #TNR_ID01
	FROM #TNR_ed01
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,Program
	, FacilityLongName
	--add overall indicator
	UNION
	SELECT 	'01' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Percent of ED Patients Admitted to Hospital Within 10 Hours' as 'IndicatorName'
	, sum(EDP_AdmitWithinTarget) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum(EDP_AdmitWithinTarget)/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P0' as 'Format'
	,  CASE WHEN FiscalPeriodLong  <'2019-01' THEN 0.55
		    WHEN FiscalPeriodLong >='2019-01' THEN 0.58
	END as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #TNR_ed01
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

-----------------------------------------------
--ID02 Percent of ED patients admitted to hospital between 10-11 hours (near misses) - P4P
-----------------------------------------------
	/*
	Purpose: To compute the percentage of ED visits not admitted within 10-11 hours.
	Author: Hans Aisake
	Date Created: April 1, 2019
	Date Updated: 
	Inclusions/Exclusions:
	Comments:
	*/

	--preprocess ED data and identify reporting time frames
	IF OBJECT_ID('tempdb.dbo.#tnr_ed02') IS NOT NULL DROP TABLE #tnr_ed02;
	GO

	--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
	SELECT 	T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, X.[EDP_AdmitMissedTarget60min]
	, X.Program
	, X.FacilityLongName
	INTO #TNR_ed02
	FROM
	(
		SELECT ED.StartDate
		, ED.[EDP_AdmitMissedTarget60min]
		, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
		, ED.FacilityLongName
		FROM EDMart.dbo.vwEDVisitIdentifiedRegional as ED
		LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--link to a fact table that identifies which program each unit goes to; not maintained by DMR
		ON ED.InpatientNursingUnitID= MAP.NursingUnitID			--same nursing unit id
		AND ED.StartDate BETWEEN MAP.StartDate AND MAP.EndDate	--within mapping dates; you could argue for inpatient date, but it's a minor issue
		WHERE ED.FacilityShortName='RHS'
		AND ED.admittedflag=1
		AND ED.StartDate >= (SELECT MIN(FiscalPeriodStartDate) FROM #TNR_FPReportTF)
		--AND IsNACRSSubmitted ='Y'	--this is not a well known filter but it only applies to about 1/1000 ed visits; this mostly delays initial reporting for several days and I've removed it. It seams to be non-value add
		AND not exists (SELECT 1 FROM EDMart.dbo.vwDTUDischargedHome as Z WHERE ED.continuumID=Z.ContinuumID)	--exclude clients discharged home from the DTU 
	) as X
	INNER JOIN #TNR_FPReportTF as T						--only keep reporting weeks we care about
	ON X.startdate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate
	;
	GO

	-----------------------------------------------
	--generate weekly indicators and store the data
	-----------------------------------------------
	IF OBJECT_ID('tempdb.dbo.#TNR_ID02') IS NOT NULL DROP TABLE #TNR_ID02;
	GO

	SELECT 	'02' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Percent of ED Patients Admitted to Hospital between 10-11 Hours (Near-Misses)' as 'IndicatorName'
	, sum([EDP_AdmitMissedTarget60min]) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum([EDP_AdmitMissedTarget60min])/count(*) as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	INTO #TNR_ID02
	FROM #TNR_ed02
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, Program
	, FacilityLongName
	--add overall indicator
	UNION
	SELECT 	'02' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Percent of ED Patients Admitted to Hospital between 10-11 Hours (Near-Misses)' as 'IndicatorName'
	, sum([EDP_AdmitMissedTarget60min]) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum([EDP_AdmitMissedTarget60min])/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #TNR_ed02
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

-----------------------------------------------
--ID03 Percent of ED patients admitted to hospital longer than 18 hours (long delays)- P4P
-----------------------------------------------
	/*
	Purpose: Compute the Percent of ED patients admitted to hospital longer than 18 hours.
	Author: Hans Aisake
	Date Created: April 1, 2019
	Date Updated: 
	Inclusions/Exclusions:
	Comments:
	*/

	--preprocess ED data and identify reporting time frames
	IF OBJECT_ID('tempdb.dbo.#tnr_ed03') IS NOT NULL DROP TABLE #tnr_ed03;
	GO

	--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
	SELECT 	T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, X.[Long_Delay]
	, X.Program
	, X.FacilityLongName
	INTO #TNR_ed03
	FROM
	(
		SELECT ED.StartDate
		, CASE WHEN StarttoDispositionExclCDUtoBedRequest > 1080 THEN 1 ELSE 0 END AS 'Long_Delay'
		, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
		, ED.FacilityLongName
		FROM EDMart.dbo.vwEDVisitIdentifiedRegional as ED
		LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--link to a fact table that identifies which program each unit goes to; not maintained by DMR
		ON ED.InpatientNursingUnitID= MAP.NursingUnitID			--same nursing unit id
		AND ED.StartDate BETWEEN MAP.StartDate AND MAP.EndDate	--within mapping dates; you could argue for inpatient date, but it's a minor issue
		WHERE ED.FacilityShortName='RHS'
		AND ED.admittedflag=1
		AND ED.StartDate >= (SELECT MIN(FiscalPeriodStartDate) FROM #TNR_FPReportTF)
		--AND IsNACRSSubmitted ='Y'	--this is not a well known filter but it only applies to about 1/1000 ed visits; this mostly delays initial reporting for several days and I've removed it. It seams to be non-value add
		AND not exists (SELECT 1 FROM EDMart.dbo.vwDTUDischargedHome as Z WHERE ED.continuumID=Z.ContinuumID)	--exclude clients discharged home from the DTU 
	) as X
	INNER JOIN #TNR_FPReportTF as T						--only keep reporting weeks we care about
	ON X.startdate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate
	;
	GO
	
	-----------------------------------------------
	--generate indicators and store the data
	-----------------------------------------------
	IF OBJECT_ID('tempdb.dbo.#TNR_ID03') IS NOT NULL DROP TABLE #TNR_ID03;
	GO

	SELECT 	'03' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Percent of ED Patients Admitted to Hospital longer than 18 Hours (Long Delays)' as 'IndicatorName'
	, sum([Long_Delay]) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum([Long_Delay])/count(*) as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P0' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	INTO #TNR_ID03
	FROM #TNR_ed03
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,Program
	, FacilityLongName
	--add overall indicator
	UNION
	SELECT 	'03' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Percent of ED Patients Admitted to Hospital longer than 18 Hours (Long Delays)' as 'IndicatorName'
	, sum([Long_Delay]) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum([Long_Delay])/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P0' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #TNR_ed03
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,FacilityLongName
	;
	GO

-----------------------------------------------
-- ID04 ALOS 
-----------------------------------------------
	
	--pulls in relevant fields from a finance mart tabel that is supposed to be a copy of a finance ALOS report
	IF OBJECT_ID('tempdb.dbo.#TNR_financeALOS_04') IS NOT NULL DROP TABLE #TNR_financeALOS_04;
	GO

	SELECT  F.FiscalPeriod as 'FiscalPeriodLong'
	, D.FiscalPeriodEndDate		--get the fiscal period date from another table
	, CASE WHEN sector='' AND program='' AND subprogram ='' AND costcenter ='' THEN 'Overall'	--rename the overall label to be consistent with other indicators
		   ELSE Program
	END as 'Program'
	, 'Richmond Hospital' as 'Facility'
	, LOS as 'Inpatient_Days'					--this inptient days is different from waht I computed in the other indicators
	, Visits as 'Visits'
	, 1.0*LOS/Visits as 'ALOS'
	INTO #TNR_financeALOS_04
	FROM [FinanceMart].[LOS].[ALOSPeriodicReport] as F
	INNER JOIN #TNR_FPReportTF as D		
	ON F.FiscalPeriod=D.FiscalPeriodLong		--only periods of interest in the report
	where RptGrouping = 'Program By Director'	--program groupings
	AND entity =  'Richmond Health Services'	--richmond only
	AND subprogram =''							--don't want program breakdowns
	;

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID04') IS NOT NULL DROP TABLE #TNR_ID04;
	GO

	--program specific
	SELECT '04' as 'IndicatorID'
	, Facility
	, Program
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Average Length of Stay' as 'IndicatorName' 
	, Inpatient_Days as 'Numerator'
	, Visits as 'Denominator'
	, 1.0*Inpatient_Days/Visits as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	,  NULL as 'Target'
	, 'FinaceMart-ALOS Periodic Report' as 'DataSource'
	, CASE WHEN Program = 'Overall' THEN 1
		   ELSE 0
	END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	INTO #TNR_ID04
	FROM #TNR_financeALOS_04
	WHERE program !='RHS COO Unallocated'
	--overall is included in the source data and doesn't need to be added here like the other indicators
	;
	GO

-----------------------------------------------
-- ID05 Number of Long Length of Stay (> 30 days) patients snapshot
-----------------------------------------------
	/*
	Purpose: To compute the LLOS census of currently waiting on the thursday week end of each week. (Snapshot)
	Fundamentally, It seams like we are trying our best to just focus on true inpatients in true inpatient units.
	It's not clear though what the expected definition is.

	The P4P query applies filters in a way that doesn't make this quite clear so I've switched it around here.

	Author: Hans Aisake
	Date Created: June 14, 2018
	Date Updated: April 1, 2018
	Inclusions/Exclusions:
		- true inpatient records only
		- excludes newborns
	Comments:
		I took the base query for indicator 471 for the BSC version FROM Emily, but modified it to be richmond specific.
		Targets are absed on the BSI fiscal period targets. If it is a snapshot it shouldn't be directly comprable to the thursday week end.
		It doens't match the BSc front page because they average accross several periods where as here we just show what it was for the period.
	
	*/
	-------------------
	--pull LLOS (>30 days) census data for patients 
	------------------
	IF OBJECT_ID('tempdb.dbo.#TNR_cLLOS_Census') IS NOT NULL DROP TABLE #TNR_cLLOS_Census;
	GO

	SELECT  
	CASE WHEN ADTC.AdmittoCensusDays > 210 THEN 180
		 WHEN ADTC.AdmitToCensusDays BETWEEN 31 AND 210 THEN ADTC.AdmittoCensusDays-30 
		 ELSE 0
	END as 'LLOSDays'
	, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
	, D.FiscalPeriodLong
	, D.FiscalPeriodEndDate
	, ADTC.FacilityLongName
	, ADTC.PatientId
	INTO #TNR_cLLOS_Census
	FROM ADTCMart.[ADTC].[vwCensusFact] as ADTC
	INNER JOIN #TNR_FPReportTF as D 
	ON ADTC.CensusDate =D.FiscalPeriodEndDate	--pull census for the fiscal period end, as a snapshot
	INNER JOIN #adtcNUClassification_tnr as NU
	ON ADTC.NursingUnitCode=NU.NursingUnitCode					--match on nursing unit
	AND NU.NULevel='Acute'										--only inpatient units
	LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP		--get program
	ON ADTC.NursingUnitCode=MAP.nursingunitcode					--match on nursing unit
	AND ADTC.CensusDate BETWEEN MAP.StartDate AND MAP.EndDate	--active program unit mapping dates
	WHERE ADTC.age>1				--P4P standard definition to exclude newborns.
	AND ADTC.AdmittoCensusDays > 30	--only need the LLOS patients, I'm not interested in proportion of all clients
	AND (ADTC.HealthAuthorityName = 'Vancouver Coastal' -- only include residents of Vancouver Coastal
	OR (ADTC.HealthAuthorityName = 'Unknown BC' AND (ADTC.IsHomeless = '1' OR ADTC.IsHomeless_PHC = '1'))) -- Include Unknown BC homeless population
	AND ADTC.[Site] ='rmd'									--only include census at Richmond
	AND ADTC.AccountType in ('I', 'Inpatient', '391')		--the code is different for each facility. Richmond is Inpatient
	AND ADTC.AccountSubtype in ('Acute')					--the true inpatient classification is different for each site. This is the best guess for Richmond
	;
	GO

	
	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID05') IS NOT NULL DROP TABLE #TNR_ID05;
	GO

	SELECT '05' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Number of Long Length of Stay (> 30 days) patients snapshot' as 'IndicatorName' 
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, SUM(LLOSDays) as 'Value'
	 , 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, NULL as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	INTO #TNR_ID05
	FROM #TNR_cLLOS_Census
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,Program
	, FacilityLongName
	--add overall
	UNION
	SELECT '05' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Number of Long Length of Stay (> 30 days) patients snapshot' as 'IndicatorName' 
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, SUM(LLOSDays) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CASE WHEN FiscalPeriodEndDate BETWEEN '2012-04-01' AND '2013-03-31' THEN 1697
		   WHEN FiscalPeriodEndDate BETWEEN '2013-04-01' AND '2014-03-31' THEN 1697
		   WHEN FiscalPeriodEndDate BETWEEN '2014-04-01' AND '2015-03-31' THEN 1432
		   WHEN FiscalPeriodEndDate BETWEEN '2015-04-01' AND '2016-03-31' THEN 1454
		   WHEN FiscalPeriodEndDate BETWEEN '2016-04-01' AND '2017-03-31' THEN 1381
		   WHEN FiscalPeriodEndDate BETWEEN '2017-04-01' AND '2018-03-31' THEN 1376
		   WHEN FiscalPeriodEndDate BETWEEN '2018-04-01' AND '2019-03-31' THEN 1637 
		   ELSE NULL
	END as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #TNR_cLLOS_Census
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

	--remove population and family health because it's not right for this indicator
	DELETE FROM #TNR_ID05 WHERE Program ='Pop & Family Hlth & Primary Cr'
	GO

	--append 0's ; might be something wrong here
	INSERT INTO #TNR_ID05 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall,Scorecard_eligible, IndicatorCategory)
	SELECT 	'05' as 'IndicatorID'
	, p.facility
	, p.IndicatorName
	, P.Program
	, P.TimeFrame
	, P.TimeFrameLabel as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, 0 as 'Value'	--proper 0's
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CASE WHEN P.timeFrame BETWEEN '2012-04-01' AND '2013-03-31' and P.Program ='Overall' THEN 1697
		   WHEN P.timeFrame BETWEEN '2013-04-01' AND '2014-03-31' and P.Program ='Overall' THEN 1697
		   WHEN P.timeFrame BETWEEN '2014-04-01' AND '2015-03-31' and P.Program ='Overall' THEN 1432
		   WHEN P.timeFrame BETWEEN '2015-04-01' AND '2016-03-31' and P.Program ='Overall' THEN 1454
		   WHEN P.timeFrame BETWEEN '2016-04-01' AND '2017-03-31' and P.Program ='Overall' THEN 1381
		   WHEN P.timeFrame BETWEEN '2017-04-01' AND '2018-03-31' and P.Program ='Overall' THEN 1376
		   WHEN P.timeFrame BETWEEN '2018-04-01' AND '2019-03-31' and P.Program ='Overall' THEN 1637 
		   ELSE NULL
	END as 'Target'
	, 'ADTCMart' as 'DataSource'
	, CASE WHEN P.Program ='Overall' THEN 1 ELSE 0 END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #placeholder as P
	LEFT JOIN #TNR_ID05 as I
	ON P.facility=I.Facility
	AND P.IndicatorId=I.IndicatorID
	AND P.Program=I.Program
	AND P.TimeFrame=I.TimeFrame
	WHERE P.IndicatorID= (SELECT distinct indicatorID FROM #TNR_ID05)
	AND I.[Value] is NULL
	;
	GO
		
-----------------------------------------------
-- ID06 Discharged Long Length of Stay (> 30 days) patient days excludes newborns
-----------------------------------------------
	/*
	Purpose: To compute the volume of discharges that were LLOS >30 days patients. 
	Author: Hans Aisake
	Date Created: June 14, 2018
	Date Updated: April 1, 2019
	Inclusions/Exclusions:
		- true inpatient records only
		- excludes newborns
	Comments:
	- The balanced scorecard truncates the LLOS days at 180. Peter says this is an artificat we inherited from the Ministry of Health neigh on 20 years ago.
	- It's not clear if this is a value add, value negative, or neutral modification.
	*/
	IF OBJECT_ID('tempdb.dbo.#TNR_LLOS_06') IS NOT NULL DROP TABLE #TNR_LLOS_06;
	GO

	SELECT T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, T.FiscalPeriodStartDate
	, CASE WHEN ADTC.LOSDays > 210 THEN 180
		   WHEN ADTC.LOSDays BETWEEN 31 and 210 THEN ADTC.LOSDays-30 
		   ELSE 0
	END as 'LLOSDays'	--truncates at 180 on the BSc
	, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
	,1 as 'casecount'
	, ADTC.DischargeFacilityLongName
	INTO #TNR_LLOS_06
	FROM ADTCMart.[ADTC].[vwAdmissionDischargeFact] as ADTC
	INNER JOIN #TNR_FPReportTF as T
	ON ADTC.AdjustedDischargeDate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate	--discharge in reporting timeframe
	LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP		--to get the program
	ON ADTC.DischargeNursingUnitCode=MAP.nursingunitcode		--same code
	AND ADTC.AdjustedDischargeDate BETWEEN MAP.StartDate AND MAP.EndDate	--unit program mapping dates
	WHERE ADTC.[site]='rmd'	--richmond only
	and ADTC.[AdjustedDischargeDate] is not null	--must have a discharge date
	and ADTC.[DischargePatientServiceCode]<>'NB'	--exclude newborns
	and ADTC.[AccountType]='I'						--inpatient cases only
	and ADTC.[AdmissionAccountSubType]='Acute'		--inpatient subtype
	and LEFT(ADTC.DischargeNursingUnitCode,1)!='M'	--excludes ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')
	and ADTC.LOSDays>30		--only LLOS cases
	;
	GO

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID06') IS NOT NULL DROP TABLE #TNR_ID06;
	GO

	SELECT '06' as 'IndicatorID'
	, DischargeFacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Discharged Long Length of Stay (> 30 days) patient days excludes newborns' as 'IndicatorName' 
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, sum(LLOSDays) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, NULL as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	INTO #TNR_ID06
	FROM #TNR_LLOS_06
	GROUP BY FiscalPeriodLong
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	,Program
	,DischargeFacilityLongName
	--add overall
	UNION
	SELECT '06' as 'IndicatorID'
	, DischargeFacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Discharged Long Length of Stay (> 30 days) patient days excludes newborns' as 'IndicatorName' 
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, sum(LLOSDays) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, 13210.0/365*DATEDIFF(day,fiscalperiodstartdate, fiscalperiodenddate) as 'Target'	--change the target to account for # of days in FP
	, 'ADTCMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #TNR_LLOS_06
	GROUP BY FiscalPeriodLong
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	,DischargeFacilityLongName
	;
	GO

	--append 0's for groups where no data was present but was expected
	INSERT INTO #TNR_ID06 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall,Scorecard_eligible, IndicatorCategory)
	SELECT 	'06' as 'IndicatorID'
	, p.facility
	, p.IndicatorName
	, P.Program
	, P.TimeFrame
	, P.TimeFrameLabel as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, 0 as 'Value'	--proper 0's
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CASE WHEN P.Program='Overall' THEN 13210.0/365*DATEDIFF(day, P.fiscalperiodstartdate, P.TimeFrame) ELSE NULL END as 'Target'
	, 'ADTCMart' as 'DataSource'
	, CASE WHEN P.Program ='Overall' THEN 1 ELSE 0 END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	FROM #placeholder as P
	LEFT JOIN #TNR_ID06 as I
	ON P.facility=I.Facility
	AND P.IndicatorId=I.IndicatorID
	AND P.Program=I.Program
	AND P.TimeFrame=I.TimeFrame
	WHERE P.IndicatorID= (SELECT distinct indicatorID FROM #TNR_ID06)
	AND I.[Value] is NULL
	;

-----------------------------------------------
-- ID07 ALC rate Discharge Based Excluding NewBorns
-----------------------------------------------
	/*
	Purpose: To compute how many inpatient days were ALC vs. all inpatient days for patients discharged in the reporting time frame.

	# ALC inpatient days of discharges in time frame / # inpatient days of discharges in time frame (ALC and non-ALC)

	Author: Hans Aisake
	Date Created: June 14, 2018
	Date Updated: Oct 19, 2018
	Inclusions/Exclusions:
		- true inpatient records only
		- excludes newborns
	Comments:
	*/

	--links census data which has ALC information with admission/discharge information
	IF OBJECT_ID('tempdb.dbo.#TNR_discharges_07') IS NOT NULL DROP TABLE #TNR_discharges_07;
	GO

	SELECT AccountNumber
	, T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, A.DischargeNursingUnitDesc
	, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
	, A.DischargeFacilityLongName
	, A.[site]
	INTO #TNR_discharges_07
	FROM ADTCMart.[ADTC].[vwAdmissionDischargeFact] as A
	INNER JOIN #TNR_FPReportTF as T						--identify the week
	ON A.AdjustedDischargeDate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate
	LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--identify the program
	ON A.DischargeNursingUnitCode = MAP.nursingunitcode
	AND A.AdjustedDischargeDate BETWEEN MAP.StartDate AND MAP.EndDate
	WHERE A.[Site]='rmd'
	AND A.[AdjustedDischargeDate] is not null		--discharged
	AND A.[DischargePatientServiceCode]<>'NB'		--not a new born
	AND A.[AccountType]='I'							--inpatient at richmond only
	AND A.[AdmissionAccountSubType]='Acute'			--subtype acute; true inpatient
	AND LEFT(A.DischargeNursingUnitCode,1)!='M'	--excludes ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')
	AND A.AdjustedDischargeDate > (SELECT MIN(FiscalPeriodStartDate) FROM #TNR_FPReportTF)	--discahrges in reporting timeframe
	;
	GO

	--links census data which has ALC information with admission/discharge information
	IF OBJECT_ID('tempdb.dbo.#TNR_ALC_discharges_07') IS NOT NULL DROP TABLE #TNR_ALC_discharges_07;
	GO

	--pull in ALC days per case
	SELECT C.AccountNum
	, SUM(CASE WHEN patientservicecode like 'AL[0-9]' or patientservicecode like 'A1[0-9]' THEN 1 ELSE 0 END) as 'ALC_Days'
	, COUNT(*) as 'Census_Days'
	INTO #TNR_ALC_discharges_07
	FROM ADTCMart.adtc.vwCensusFact as C
	WHERE exists (SELECT 1 FROM #TNR_discharges_07 as Y WHERE C.AccountNum=Y.AccountNumber AND C.[Site]=Y.[Site])
	GROUP BY C.AccountNum
	;
	GO

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID07') IS NOT NULL DROP TABLE #TNR_ID07;
	GO

	SELECT 	'07' as 'IndicatorID'
	, X.DischargeFacilityLongName as 'Facility'
	, X.Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'ALC Rate Based on Discharges' as 'IndicatorName'
	, SUM(Y.ALC_Days) as 'Numerator'
	, SUM(Y.Census_Days) as 'Denominator'
	, 1.0*SUM(Y.ALC_Days)/SUM(Y.Census_Days) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P0' as 'Format'
	, CASE WHEN X.FiscalPeriodEndDate between '4/1/2013' and '3/31/2014' THEN 0.099
		  WHEN X.FiscalPeriodEndDate between '4/1/2014' and '3/31/2015' THEN 0.11
		  WHEN X.FiscalPeriodEndDate between '4/1/2015' and '3/31/2016' THEN 0.115
		  ELSE 0.115 
	END as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	INTO #TNR_ID07
	FROM #TNR_discharges_07 as X
	LEFT JOIN #TNR_ALC_discharges_07 as Y
	ON X.AccountNumber=Y.AccountNum
	GROUP BY X.FiscalPeriodLong
	, X.FiscalPeriodEndDate
	, X.Program
	, X.DischargeFacilityLongName
	--add overall
	UNION 
	SELECT '07' as 'IndicatorID'
	, X.DischargeFacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'ALC Rate Based on Discharges' as 'IndicatorName'
	, SUM(Y.ALC_Days) as 'Numerator'
	, SUM(Y.Census_Days) as 'Denominator'
	, 1.0*SUM(Y.ALC_Days)/SUM(Y.Census_Days) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P0' as 'Format'
	, CASE WHEN X.FiscalPeriodEndDate between '4/1/2013' and '3/31/2014' THEN 0.099
		   WHEN X.FiscalPeriodEndDate between '4/1/2014' and '3/31/2015' THEN 0.11
		   WHEN X.FiscalPeriodEndDate between '4/1/2015' and '3/31/2016' THEN 0.115
		   ELSE 0.115 
	END as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	FROM #TNR_discharges_07 as X
	LEFT JOIN #TNR_ALC_discharges_07 as Y
	ON X.AccountNumber=Y.AccountNum
	GROUP BY X.FiscalPeriodLong
	, X.FiscalPeriodEndDate
	, X.DischargeFacilityLongName
	;
	GO

-----------------------------------------------
-- ID08 Discharges Actual vs. Predicted
-----------------------------------------------
	--need to move this elsewhere and get it from CapPlanGO


-----------------------------------------------
-- ID09 Number of all case readmission to same site within 28 days. iCare Definition.
-----------------------------------------------
	--pulled from iCareMart and convert the wkend to a date; for efficiency of joins
	IF OBJECT_ID('tempdb.dbo.#tnr_28dreadd') is not null DROP TABLE #tnr_28dreadd;
	GO

	SELECT [Facility]
	, [GroupName]
	, [Indicator]
	, [Value]
	, CONVERT(datetime, CONVERT(varchar(8),WkEnd),112) as 'ThursdayWkEnd'
	INTO #tnr_28dreadd
	FROM [ICareMart].[dbo].[icareFinalComputationsUnpivot]
	WHERE indicator='Readmission28D'
	AND facility='RHS'
	;
	GO

	--assigned fiscal periods and aggregate the data
	IF OBJECT_ID('tempdb.dbo.#tnr_28dreadd2') is not null DROP TABLE #tnr_28dreadd2;
	GO

	SELECT D.FiscalPeriodLong
	, facility
	, D.FiscalPeriodStartDate
	, D.FiscalPeriodEndDate
	, 'Number of Readmissions within 28 days' as 'IndicatorName'
	, MAP.NewProgram as 'Program'
	, SUM([Value]) as 'NumReadmissions'
	INTO #tnr_28dreadd2
	FROM #tnr_28dreadd as X
	INNER JOIN #TNR_FPReportTF as D
	ON X.ThursdayWkEnd BETWEEN D.FiscalPeriodStartDate AND D.FiscalPeriodEndDate
	INNER JOIN DSSI.dbo.RH_VisibilityWall_NU_PROGRAM_MAP_ADTC as MAP
	ON GroupName=Map.nursingunitcode
	AND X.ThursdayWkEnd BETWEEN MAP.StartDate AND MAP.EndDate
	GROUP BY D.FiscalPeriodLong
	, D.FiscalPeriodStartDate
	, D.FiscalPeriodEndDate
	, Facility
	, indicator
	, Map.NewProgram 
	;

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID09') IS NOT NULL DROP TABLE #TNR_ID09;
	GO

	SELECT '09' as 'IndicatorID'
	, CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END as 'Facility'
	, Program
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, [NumReadmissions] as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, NULL as 'Target'
	, 'iCareMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	INTO #TNR_ID09
	FROM #tnr_28dreadd2
	--add overall
	UNION
	SELECT '09' as 'IndicatorID'
	, CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, SUM([NumReadmissions]) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, 18*1.0*DATEDIFF(day,fiscalperiodstartdate, fiscalperiodenddate)/7 as 'Target'	--weekly target of iCare overall * # of weeks in the fiscsal period, won't be an int for P1 and P13.
	, 'iCareMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	FROM #tnr_28dreadd2
	GROUP BY CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	, FiscalPeriodLong
	, IndicatorName
	;
	GO

-----------------------------------------------
-- ID10 Number of Beds Occupied (excl. Mental Health, ED, DTU, PAR, Periops)   --- currently Average Census
-----------------------------------------------
	
	--compute and store indicators
	IF OBJECT_ID('tempdb.dbo.#TNR_inpatientDaysPGRM') IS NOT NULL DROP TABLE #TNR_inpatientDaysPGRM;
	GO

	SELECT X.FiscalPeriodEndDate
	, X.FiscalPeriodStartDate
	, X.FiscalPeriodLong
	, X.EntityDesc				--I might want to move entity into a mapping column as that makes more sense for flexibility
	, Y.LambertProgram  as 'ProgramDesc'
	, SUM(BudgetedCensusDays) as 'BudgetedCensusDays'
	, SUM(ActualCensusDays) as 'ActualCensusDays'
	INTO #TNR_inpatientDaysPGRM
	FROM #tnr_inpatientDaysByCC as X
	INNER JOIN [DSSI].[dbo].[AISAKE_TNR_CCMAPS2] as Y
	ON X.FinSiteID=Y.FinSite
	AND X.CostCenterCode =Y.CCCode
	AND Y.LambertProgram is not NULL	--this is where you choose your map
	GROUP BY X.FiscalPeriodEndDate
	, X.FiscalPeriodStartDate
	, X.FiscalPeriodLong
	, X.EntityDesc
	, Y.LambertProgram 
	;
	GO

	--compute and store indicators
	IF OBJECT_ID('tempdb.dbo.#TNR_ID10') IS NOT NULL DROP TABLE #TNR_ID10;
	GO
	
	SELECT '10' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, [ProgramDesc] as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Inpatient census per day in the period' as 'IndicatorName'
	, SUM(ActualCensusDays) as 'Numerator'
	, DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate) as 'Denominator'
	, 1.0*SUM(ActualCensusDays)/DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate)  as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, 1.0*SUM(BudgetedCensusDays)/DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate) as 'Target'		--based on budget
	, 'FinanceMart' as 'DataSource'	--Lamberts groupings
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	INTO #TNR_ID10
	FROM #TNR_inpatientDaysPGRM
	WHERE Entitydesc ='Richmond Health Services'
	GROUP BY EntityDesc
	, ProgramDesc
	, FiscalPeriodLong
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	--add overall
	UNION
	SELECT '10' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Inpatient census per day in the period' as 'IndicatorName'
	, SUM(ActualCensusDays) as 'Numerator'
	, DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate) as 'Denominator'
	, 1.0*SUM(ActualCensusDays)/DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate)  as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, 1.0*SUM(BudgetedCensusDays)/DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate) as 'Target'		--based on budget
	, 'FinanceMart' as 'DataSource'	--Lamberts groupings
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	FROM #TNR_inpatientDaysPGRM
	WHERE Entitydesc ='Richmond Health Services'
	GROUP BY EntityDesc
	, FiscalPeriodLong
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	;
	GO
	
	--remove these breakdowns so they don't show up in the report; In real terms this is the Temporary Bed Unit taht was on R6N but it was paid under an unallocated cost center
	--we can't possibly account for this in automated report as it requires to much investigation.
	DELETE FROM #TNR_ID10 WHERE Program='RHS COO Unallocated';
	GO

-----------------------------------------------
-- ID11 Beds occupied as a % of budgeted bed capacity (excl. Mental Health, ED ,DTU, PAR, Periop) 
-----------------------------------------------
	--a finance mart based definition; doesn't agree with the historical vancouver extract likely because of labels.
	IF OBJECT_ID('tempdb.dbo.#TNR_ID11') IS NOT NULL DROP TABLE #TNR_ID11;
	GO

	SELECT '11' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, [ProgramDesc] as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Beds occupied as a % of budgeted bed capacity' as 'IndicatorName'
	, ActualCensusDays as 'Numerator'
	, BudgetedCensusDays as 'Denominator'
	, 1.0*ActualCensusDays/ IIF(BudgetedCensusDays =0, 1, BudgetedCensusDays ) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  NULL as 'Target'
	, 'FinanceMart' as 'DataSource'	--Lamberts groupings
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	INTO #TNR_ID11
	FROM #TNR_inpatientDaysPGRM
	WHERE EntityDesc='Richmond Health Services'		--only want the richmond IP days.
	--add overall indicator
	UNION
	SELECT '11' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Beds occupied as a % of budgeted bed capacity' as 'IndicatorName'
	, SUM(ActualCensusDays) as 'Numerator'
	, SUM(BudgetedCensusDays) as 'Denominator'
	, 1.0*SUM(ActualCensusDays)/ IIF(SUM(BudgetedCensusDays) =0, 1, SUM(BudgetedCensusDays) ) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  NULL as 'Target'
	, 'FinanceMart' as 'DataSource'	--Lamberts groupings
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	FROM #TNR_inpatientDaysPGRM
	WHERE EntityDesc='Richmond Health Services'		--only want the richmond IP days.
	GROUP BY EntityDesc, FiscalPeriodEndDate, FiscalPeriodLong
	;
	GO

	--remove these breakdowns so they don't show up in the report; In real terms this is the Temporary Bed Unit taht was on R6N but it was paid under an unallocated cost center
	--we can't possibly account for this in automated report as it requires to much investigation.
	DELETE FROM #TNR_ID11 WHERE Program='RHS COO Unallocated';
	GO

--------------------------------------
-- ID12 OT rate (hr based)
---------------------------------------
	/*
	Purpose: To pull the overtime hours and productive horus from FinanceMart
	Author: Hans Aisake
	Date Created: October 3, 2018
	Date Modified: May 7, 2019
	Inclusions/Exclusions:
	Comments:
		Carolina provided the specs for this and it's similar to the finance portal queries. I'm not sure they are exactly equal because of all the parameters in the portal query, but the main tables are the same.
		HR extract based definition in version 6 or earlier

	*/
	
	--pull overtime hours from FinanceMart tables
	IF OBJECT_ID('tempdb.dbo.#tnr_otHours') is not null DROP TABLE #tnr_otHours;
	GO

	SELECT productiveHours.EntityDesc
	, productiveHours.ProgramDesc
	--, productiveHours.SubProgramDesc
	--, productiveHours.CostCenterCode
	--, productiveHours.FinSiteID
	, productiveHours.[FiscalYearLong]
	, productiveHours.[FiscalPeriod] 
	, productiveHours.Act_ProdHrs
	--, ISNULL(casualHours.Casual_ProdHrs,0) as 'Casual_ProdHrs'
	--, productiveHours.Act_ProdHrs - ISNULL(casualHours.Casual_ProdHrs,0) as 'Act_ProdHrs'	-- The OT report didn't exclude casual hours
	, ISNULL(otHours.Act_OTHrs,0) as 'Act_OTHrs'
	--, ISNULL(otHours.Act_OTHrs,0) - ISNULL(casualHours.Casual_OTHrs,0) as 'Act_OTHrs'
	--, casualHours.Casual_OTHrs
	, productiveHours.Bud_ProdHrs	-- The OT report didn't exclude casual hours
	, ISNULL(otHours.Bud_OTHrs,0) as 'Bud_OTHrs'
	INTO #tnr_otHours
	FROM
	(	
		SELECT epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END as 'ProgramDesc'
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, epsp.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod]  
		,Sum([SumCodeHrs]) as 'Act_ProdHrs'   
		,Sum([BudgetHrs]) as 'Bud_ProdHrs'
		FROM [FinanceMart].[dbo].[SumCodeHrsSummary] as schrs
		INNER JOIN [FinanceMart].[Dim].[CostCenter] as cc
		ON schrs.CostCenter = cc.CostCenterCode
		INNER JOIN [FinanceMart].Dim.CostCenterBusinessUnitEntitySite as ccbues
		ON cc.CostCenterID = ccbues.CostCenterID 
		AND schrs.FinSiteID=ccbues.FinSiteID
		INNER JOIN [FinanceMart].[Finance].[EntityProgramSubProgram] as EPSP
		ON ccbues.CostCenterBusinessUnitEntitySiteID = EPSP.CostCenterBusinessUnitEntitySiteID		--same ccentitysiteid
		where sumCodeID <= 199							--productive hours
		and EntityDesc in('Richmond Health Services')		--focus on these entities
		and EntityProgramDesc in ('RH Clinical'	,'RHS HSDA')	--rileys file had both of these included in the total richmond numbers
		and FiscalYearLong >= 2015						--date cutoff
		GROUP BY epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, epsp.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod]
	) as productiveHours
	LEFT JOIN
	(	SELECT epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END as 'ProgramDesc'
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, epsp.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod] 
		, Sum([SumCodeHrs]) as 'Act_OTHrs' 
		, Sum([BudgetHrs]) as 'Bud_OTHrs' 
		FROM [FinanceMart].[dbo].[SumCodeHrsSummary] as schrs
		INNER JOIN [FinanceMart].[Dim].[CostCenter] as cc	--get cost center business unit entity site id
		ON schrs.CostCenter = cc.CostCenterCode		--same cost center
		INNER JOIN FinanceMart.Dim.CostCenterBusinessUnitEntitySite as ccbues
		ON cc.CostCenterID = ccbues.CostCenterID		--same cost center
		AND schrs.FinSiteID=ccbues.FinSiteID			--same financial site
		JOIN [FinanceMart].[Finance].[EntityProgramSubProgram] as EPSP
		ON ccbues.CostCenterBusinessUnitEntitySiteID = EPSP.CostCenterBusinessUnitEntitySiteID
		WHERE sumCodeID = 104							--overtime hours
		and EntityDesc in('Richmond Health Services')		--focus on these entities
		and EntityProgramDesc in ('RH Clinical'	,'RHS HSDA')	--rileys file had both of these included in the total richmond numbers
		AND FiscalYearLong >= 2015						--date cutoff
		GROUP BY epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, epsp.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod]
	) as otHours
	ON  productiveHours.EntityDesc = otHours.EntityDesc					--same entity
	AND productiveHours.ProgramDesc = otHours.ProgramDesc				--same program
	--AND productiveHours.SubProgramDesc = otHours.SubProgramDesc			--same sub program
	--AND productiveHours.CostCenterCode = otHours.CostCenterCode				--same cost center
	--AND productiveHours.FinSiteID = otHours.FinsiteID				--same fine site
	AND productiveHours.[FiscalYearLong] = otHours.[FiscalYearLong]		--same fiscal year
	AND productiveHours.[FiscalPeriod] = otHours.[FiscalPeriod]			--same fiscal period
	LEFT JOIN
	(	SELECT epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END as 'ProgramDesc'
		--, epsp.SubProgramDesc
		--, cas.[Dept#] as 'CostCenterCode'
		--, cas.[Site] as 'FinSiteID'
		, cas.[YEAR] as 'FiscalYearLong'
		, cas.[period] as 'FiscalPeriod'
		, SUM(cas.[Hour Prod]) as 'Casual_ProdHrs'
		, SUM(cas.[SickHrs]) as 'Casual_SickHrs'
		, SUM(cas.[OTHrs]) as 'Casual_OTHrs'
		FROM FinanceMart.[Finance].[vwCasualHrsFact] as cas
		LEFT JOIN FinanceMArt.Finance.EntityProgramSubProgram as epsp
		ON cas.[CostCenterBusinessUnitEntitySiteID] = epsp.CostCenterBusinessUnitEntitySiteID
		GROUP BY epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END
		--, epsp.SubProgramDesc
		--, cas.[Dept#]
		--, cas.[Site]
		, cas.[YEAR]
		, cas.[period]
	) as casualHours
	ON  productiveHours.EntityDesc = casualHours.EntityDesc					--same entity
	AND productiveHours.ProgramDesc = casualHours.ProgramDesc				--same program
	--AND productiveHours.SubProgramDesc = casualHours.SubProgramDesc		--same sub program; not reporting by this
	--AND productiveHours.CostCenterCode =casualHours.CostCenterCode		--same cost center
	--AND productiveHours.FinSiteID = casualHours.FinSiteID					--same financial site
	AND productiveHours.[FiscalYearLong] = casualHours.[FiscalYearLong]		--same fiscal year
	AND productiveHours.[FiscalPeriod] = casualHours.[FiscalPeriod]			--same fiscal period
	;
	GO

	--compute and store indicators
	IF OBJECT_ID('tempdb.dbo.#TNR_ID12') IS NOT NULL DROP TABLE #TNR_ID12;
	GO
	
	SELECT '12' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, ProgramDesc as 'Program'
	, D.fiscalPeriodEndDate as 'TimeFrame'
	, D.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Overtime hours as % of all productive hours (incl. casuals)' as 'IndicatorName'
	, OT.Act_OTHrs as 'Numerator' 
	, OT.Act_ProdHrs as 'Denominator'
	, IIF(OT.Act_ProdHrs=0, 0, 1.0*OT.Act_OTHrs/OT.Act_ProdHrs) as 'Value' --division by 0 errors are set as 0; Technically they are nulls, but 0's will stop the lines from being wierd and I feel 0/0 = 0 is fair in this case.
	, 'Below' as 'DesiredDirection'
	, 'P2' as 'Format'		--to match finance portal
	, 0.022 as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	INTO #TNR_ID12
	FROM #tnr_otHours as OT
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON OT.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND OT.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	WHERE programdesc in ('Pop & Family Hlth & Primary Cr','Mental Health & Addictions Ser','Home & Community Care','Surgery & Procedural Care','Emergency-CC & Medicine') --only want these program breakdowns
	--add overall
	UNION
	SELECT '12' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, 'Overall' as 'Program'
	, D.fiscalPeriodEndDate as 'TimeFrame'
	, D.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Overtime hours as % of all productive hours (incl. casuals)' as 'IndicatorName'
	, SUM(OT.Act_OTHrs) as 'Numerator' 
	, SUM(OT.Act_ProdHrs) as 'Denominator'
	,  IIF( SUM(OT.Act_ProdHrs)=0, 0, 1.0*SUM(OT.Act_OTHrs)/SUM(OT.Act_ProdHrs)  ) as 'Value' --division by 0 errors are set as 0; Technically they are nulls, but 0's will stop the lines from being wierd and I feel 0/0 = 0 is fair in this case.
	, 'Below' as 'DesiredDirection'
	, 'P2' as 'Format'		--to match finance portal
	, 0.022 as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	FROM #tnr_otHours as OT
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON OT.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND OT.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	WHERE OT.ProgramDesc not in ('Health Protection','BISS','Regional Clinical Services')	--remove from to match Riley's included programs. These are regional not richmond specific.
	GROUP BY EntityDesc
	, D.FiscalPeriodEndDate
	, D.FiscalPeriodLong
	;
	GO

---------------------------------------
-- ID13 Sick Rate
---------------------------------------
	/*
	Purpose: To pull the sick hours and productive horus from FinanceMart.
	Author: Hans Aisake
	Date Created: October 3, 2018
	Date Modified: May 10, 2019
	Inclusions/Exclusions:
	Comments:
		Carolina was consulted for the specs. I took some liberties to blend the query she sent and what was in the financeportal reports.
		It removes casual productive and sick hours.

		The arugment was made that casuals don't get sick hours normally, and instead they just don't get paid.
		There are also some technical issues with how we determine overtime pay and sick time pay for casuals because it's based on strange employment criteria.
		Casuals choose which days are their "days off" and get OT for comming in on those days. -Not 100% certain this is true, but I have reason to lean this way.
		Because of this we exclude casuals hours from the indicator. 
		For some areas this can be 15% of the total productive hours.
		I don't have casual budgeted productive hours and can't remove them.

	*/
	
	IF OBJECT_ID('tempdb.dbo.#tnr_sickHours') is not null DROP TABLE #tnr_sickHours;
	GO

	SELECT productiveHours.EntityDesc
	, productiveHours.ProgramDesc
	--, productiveHours.CostCenterCode
	--, productiveHours.FinSiteID
	, productiveHours.[FiscalYearLong]
	, productiveHours.[FiscalPeriod] 
	--, productiveHours.Act_ProdHrs
	, productiveHours.Act_ProdHrs - ISNULL(casualHours.Casual_ProdHrs,0) as 'Act_ProdHrs'	--we exclude casual hours for sick time
	, ISNULL(casualHours.Casual_ProdHrs,0) as 'Casual_ProdHrs'
	--, ISNULL(stHours.Act_STHrs,0) as 'Act_STHrs'
	, ISNULL(stHours.Act_STHrs,0) - ISNULL(casualHours.Casual_SickHrs,0) as 'Act_STHrs'
	--, casualHours.Casual_SickHrs
	, productiveHours.Bud_ProdHrs	--I could see an arugment to have to adjust via casual hours, but I can also see one not to. We don't plan for casual hours.
	, ISNULL(StHours.Bud_STHrs,0) as 'Bud_STHrs'
	INTO #tnr_sickHours
	FROM
	(	
		SELECT epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END as 'ProgramDesc'
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, schrs.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod]  
		, Sum(schrs.[SumCodeHrs]) as 'Act_ProdHrs'   
		, Sum(schrs.[BudgetHrs]) as 'Bud_ProdHrs'
		FROM [FinanceMart].[dbo].[SumCodeHrsSummary] as schrs
		INNER JOIN [FinanceMart].[Dim].[CostCenter] as cc
		ON schrs.CostCenter = cc.CostCenterCode
		INNER JOIN [FinanceMart].Dim.CostCenterBusinessUnitEntitySite as ccbues
		ON cc.CostCenterID = ccbues.CostCenterID 
		AND schrs.FinSiteID=ccbues.FinSiteID
		INNER JOIN [FinanceMart].[Finance].[EntityProgramSubProgram] as EPSP
		ON ccbues.CostCenterBusinessUnitEntitySiteID = EPSP.CostCenterBusinessUnitEntitySiteID		--same ccentitysiteid
		where sumCodeID <= 199							--productive hours
		AND EntityDesc in('Richmond Health Services')		--focus on these entities
		AND EntityProgramDesc in ('RH Clinical'	,'RHS HSDA')	--rileys file had both of these included in the total richmond numbers
		AND FiscalYearLong >= 2015						--date cutoff
		GROUP BY epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, schrs.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod]
	) as productiveHours
	LEFT JOIN
	(	SELECT epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END as 'ProgramDesc'
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, schrs.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod] 
		, Sum([SumCodeHrs]) as 'Act_STHrs' 
		, Sum([BudgetHrs]) as 'Bud_STHrs' 
		FROM [FinanceMart].[dbo].[SumCodeHrsSummary] as schrs
		INNER JOIN [FinanceMart].[Dim].[CostCenter] as cc	--get cost center business unit entity site id
		ON schrs.CostCenter = cc.CostCenterCode		--same cost center
		INNER JOIN FinanceMart.Dim.CostCenterBusinessUnitEntitySite as ccbues
		ON cc.CostCenterID = ccbues.CostCenterID		--same cost center
		AND schrs.FinSiteID=ccbues.FinSiteID			--same financial site
		JOIN [FinanceMart].[Finance].[EntityProgramSubProgram] as EPSP
		ON ccbues.CostCenterBusinessUnitEntitySiteID = EPSP.CostCenterBusinessUnitEntitySiteID
		WHERE sumCodeID = 206							--sick time hours
		and EntityDesc in('Richmond Health Services')		--focus on these entities
		and EntityProgramDesc in ('RH Clinical','RHS HSDA')	--rileys file had both of these included in the total richmond numbers
		AND FiscalYearLong >= 2015						--date cutoff
		GROUP BY epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END 
		--, epsp.SubProgramDesc
		--, cc.CostCenterCode
		--, schrs.FinSiteID
		, schrs.[FiscalYearLong]
		, schrs.[FiscalPeriod]
	) as stHours
	ON  productiveHours.EntityDesc = stHours.EntityDesc					--same entity
	AND productiveHours.ProgramDesc = stHours.ProgramDesc				--same program
	--AND productiveHours.SubProgramDesc = stHours.SubProgramDesc		--same sub program; not reporting by this
	--AND productiveHours.CostCenterCode =stHours.CostCenterCode				--same cost center
	--AND productiveHours.FinSiteID = stHours.FinSiteID						--same financial site
	AND productiveHours.[FiscalYearLong] = stHours.[FiscalYearLong]		--same fiscal year
	AND productiveHours.[FiscalPeriod] = stHours.[FiscalPeriod]			--same fiscal period
	LEFT JOIN
	(
		SELECT epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END as 'ProgramDesc'
		--, epsp.SubProgramDesc
		--, cas.[Dept#] as 'CostCenterCode'
		--, cas.[Site] as 'FinSiteID'
		, cas.[YEAR] as 'FiscalYearLong'
		, cas.[period] as 'FiscalPeriod'
		, SUM(cas.[Hour Prod]) as 'Casual_ProdHrs'
		, SUM(cas.[SickHrs]) as 'Casual_SickHrs'
		, SUM(cas.[OTHrs]) as 'Casual_OTHrs'
		FROM FinanceMart.[Finance].[vwCasualHrsFact] as cas
		LEFT JOIN FinanceMArt.Finance.EntityProgramSubProgram as epsp
		ON cas.[CostCenterBusinessUnitEntitySiteID] = epsp.CostCenterBusinessUnitEntitySiteID
		GROUP BY epsp.EntityDesc
		, CASE WHEN epsp.CostCenterBusinessUnitEntitySiteID =6450 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE epsp.ProgramDesc
		END
		--, epsp.SubProgramDesc
		--, cas.[Dept#]
		--, cas.[Site]
		, cas.[YEAR]
		, cas.[period]
	) as casualHours
	ON  productiveHours.EntityDesc = casualHours.EntityDesc					--same entity
	AND productiveHours.ProgramDesc = casualHours.ProgramDesc				--same program
	--AND productiveHours.SubProgramDesc = casualHours.SubProgramDesc		--same sub program; not reporting by this
	--AND productiveHours.CostCenterCode =casualHours.CostCenterCode		--same cost center
	--AND productiveHours.FinSiteID = casualHours.FinSiteID					--same financial site
	AND productiveHours.[FiscalYearLong] = casualHours.[FiscalYearLong]		--same fiscal year
	AND productiveHours.[FiscalPeriod] = casualHours.[FiscalPeriod]			--same fiscal period
	;
	GO

	--compute and store indicators
	IF OBJECT_ID('tempdb.dbo.#TNR_ID13') IS NOT NULL DROP TABLE #TNR_ID13;
	GO
	
	SELECT '13' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, ProgramDesc as 'Program'
	, D.fiscalPeriodEndDate as 'TimeFrame'
	, D.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Sick time hours as % of all productive hours (excl. casual hrs)' as 'IndicatorName'
	, ST.Act_STHrs as 'Numerator' 
	, ST.Act_ProdHrs as 'Denominator'
	, IIF(ST.Act_ProdHrs=0, 0, 1.0*ST.Act_STHrs/ST.Act_ProdHrs) as 'Value'	--division by 0 errors are set as 0; Technically they are nulls, but 0's will stop the lines from being wierd and I feel 0/0 = 0 is fair in this case.
	, 'Below' as 'DesiredDirection'
	, 'P2' as 'Format'		--to match finance portal
	, 0.022 as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	INTO #TNR_ID13
	FROM #tnr_sickHours as ST
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON ST.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND ST.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	WHERE programdesc in ('Pop & Family Hlth & Primary Cr','Mental Health & Addictions Ser','Home & Community Care','Surgery & Procedural Care','Emergency-CC & Medicine') --only want these program breakdowns
	--add overall
	UNION
	SELECT '13' as 'IndicatorID'
	, EntityDesc as 'Facility'
	, 'Overall' as 'Program'
	, D.fiscalPeriodEndDate as 'TimeFrame'
	, D.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Sick time hours as % of all productive hours (excl. casual hrs)' as 'IndicatorName'
	, SUM(ST.Act_STHrs) as 'Numerator' 
	, SUM(ST.Act_ProdHrs) as 'Denominator'
	,  IIF( SUM(ST.Act_ProdHrs)=0, 0, 1.0*SUM(ST.Act_STHrs)/SUM(ST.Act_ProdHrs)  ) as 'Value' --division by 0 errors are set as 0; Technically they are nulls, but 0's will stop the lines from being wierd and I feel 0/0 = 0 is fair in this case.
	, 'Below' as 'DesiredDirection'
	, 'P2' as 'Format'		--to match finance portal
	, 0.022 as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	FROM #tnr_sickHours as ST
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON ST.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND ST.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	WHERE ST.ProgramDesc not in ('Health Protection','BISS','Regional Clinical Services')	--remove from to match Riley's included programs. These are regional not richmond specific.
	GROUP BY EntityDesc
	, D.FiscalPeriodEndDate
	, D.FiscalPeriodLong
	;
	GO

-----------------------------------------------
-- ID14 Net Surplus/Deficit Variance (in 000's)
-----------------------------------------------
	
	-- pull expenses and revenues from the ledger; See Carolina for deeper questions why this table this way; See Hans for entity filters and program override for volunteers
	IF OBJECT_ID('tempdb.dbo.#TNR_revExpenses') is not NULL DROP TABLE #TNR_revExpenses;
	GO

	SELECT EntityDesc
	, ProgramDesc
	--, SubProgramDesc
	--, CostCenterCode
	--, [FinSiteID]
	, FiscalPeriodEndDate
	, FiscalPeriodLong
	, ISNULL(ActRevenue,0) as 'Revenue'
	, ISNULL(ActExpenses,0) as 'Expenses'
	, ISNULL(ActRevenue,0)-ISNULL(ActExpenses,0) as 'NetDeficit'
	, ISNULL(BudRevenue,0) - ISNULL(BudExpenses,0) as 'BudNetDeficit'
	INTO #TNR_revExpenses
	FROM (
		SELECT EntityDesc
		, CASE WHEN Z.costcentercode ='71400000' and a.finsiteid=650 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE ProgramDesc
		END as 'ProgramDesc'
		--, SubProgramDesc
		--, Z.CostCenterCode
		--, a.[FinSiteID]
		, q.FiscalPeriodEndDate
		, q.FiscalPeriodLong
		, -1*SUM(CASE LEFT(GLAccountCode, 1) WHEN '1' THEN BudgetAmt ELSE 0.00 END) AS 'BudRevenue'	-- -1 is to turn the negatives into positives. The numbers are stored in reverse sign to which I need
		, -1*SUM(CASE LEFT(GLAccountCode, 1) WHEN '1' THEN ActualAmt ELSE 0.00 END) AS 'ActRevenue' -- -1 is to turn the negatives into positives. The numbers are stored in reverse sign to which I need
		, SUM(CASE LEFT(GLAccountCode, 1) WHEN '1' THEN 0.00 ELSE BudgetAmt END) AS 'BudExpenses'
		, SUM(CASE LEFT(GLAccountCode, 1) WHEN '1' THEN 0.00 ELSE ActualAmt END) AS 'ActExpenses'
		FROM [FinanceMart].[Finance].[LedgerFact] a
		INNER JOIN [FinanceMart].[Finance].[EntityProgramSubProgram] b
		on a.[CostCenterBusinessUnitEntitySiteID]=b.[CostCenterBusinessUnitEntitySiteID]
		INNER JOIN [FinanceMart].[Dim].[vwFiscalPeriod] c
		on a.[FiscalPeriodEndDateID]=c.[FiscalPeriodEndDateID] 
		INNER JOIN [FinanceMart].[Dim].[GLAccount] d
		on a.[GLAccountID]=d.[GLAccountID]
		LEFT JOIN FinanceMart.dim.CostCenter as Z
		ON a.CostCenterID=Z.CostCenterID
		INNER JOIN #TNR_FPReportTF as q		--filter to reporting fiscal periods
		ON a.FiscalPeriodEndDateID = q.FiscalPeriodEndDateID
		WHERE EntityDesc = 'Richmond Health Services'			--just richmond
		AND EntityProgramDesc in( 'RH Clinical','RHS HSDA')	--want to include both
		GROUP BY EntityDesc
		, CASE WHEN Z.costcentercode ='71400000' and a.finsiteid=650 THEN 'Volunteers'	--custom remapping for me as surgery doesn't seam consistently reliable
			   ELSE ProgramDesc
		END
		--, SubProgramDesc
		--, Z.CostCenterCode
		--, a.[FinSiteID]
		, q.FiscalPeriodEndDate
		, q.FiscalPeriodLong
	) t
	--ORDER BY 1,2,3,4,5
	;
	GO

	--compute the indicator and store the result
	IF OBJECT_ID('tempdb.dbo.#TNR_ID14') is not NULL DROP TABLE #TNR_ID14;
	GO
	
	SELECT '14' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, ND.[ProgramDesc] as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Net Surplus/Deficit Variance (in 000s)' as 'IndicatorName'
	, CAST(ND.Revenue/1000 as int) as 'Numerator'
	, CAST(ND.Expenses/1000 as int) as 'Denominator'
	, CAST( (ND.Revenue - ND.Expenses)/1000 as int) as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CAST( (ND.BudNetDeficit)/1000 as int) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	INTO #TNR_ID14
	FROM #TNR_revExpenses as ND
	WHERE ND.[ProgramDesc] in ('Surgery & Procedural Care','Mental Health & Addictions Ser','Emergency-CC & Medicine','Home & Community Care','Pop & Family Hlth & Primary Cr')
	--add overall
	UNION
	SELECT '14' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Net Surplus/Deficit Variance (in 000s)' as 'IndicatorName'
	, CAST( SUM(ND.Revenue)/1000 as int ) as 'Numerator'
	, CAST( SUM(ND.Expenses)/1000 as int ) as 'Denominator'
	, CAST( (SUM(ND.Revenue) - SUM(ND.Expenses))/1000 as int ) as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CAST( SUM(ND.BudNetDeficit)/1000 as int) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	FROM #TNR_revExpenses as ND
	-- includes all programs
	GROUP BY FiscalPeriodEndDate
	, FiscalPeriodLong
	;
	GO
	
	--to get YTD for 2019
	--SELECT Program
	--, '2019-YTD'
	--, SUM(Numerator) as 'Revenue'
	--, SUM(Denominator) as 'Expenses'
	--, SUM([Value])  as 'NetDeficit'
	--FROM #TNR_ID14
	--WHERE LEFT(TimeFrameLabel,4) = '2019'	--need to make sure we have 13 periods in the above adjust #tnrreporting_fp if they aren't
	--GROUP BY Program
	
-----------------------------------------------
-- ID15 Acute Productive Hours Per Patient Day
-----------------------------------------------
/*
Purpose: To compute productive hours and inpatient days from financemart for a series of financial breakdown categories.
There may be an issue with one specific program and or unallocated funds not being mapped out to correct programs, but that can only be done with further data and manual investigation.
It is not worth sorting that out here.
Author: Hans Aisake
Date Created: Late 2018
Date Modified: April 29, 2019
Comments:

I got this query from Stella and she notes that it is updated from time to time.
I need more details to make this robust enough so all those changes are easily made.

For whatever reason we use CIHIMISgroupings  71210, 71220, 71230, 71240, 71250, 71270, 71275, 71280, 7131040 and 71290 as cost center filters.
Those groupings a high level, so the CTE finds all specific cost centers under the groupings for inclusion.
I replaced the whole #temp1 through #temp11 and #temp 3 logic with just one #tempX table because there was no reason for the 180ish lines of eduplicate code.
refer to version 4 June if you want that back, but I can't see why you would.

*/
	--get inpatient days from the section  - Finance Data from the General Ledger

	--get productive hours from the section - Finance Data from the General Ledger; not sure if this is the same as the OT and ST hours

	--compute acute productive hours per patient days and store the results
	IF OBJECT_ID('tempdb.dbo.#TNR_ID15') is not null DROP TABLE #TNR_ID15;
	GO
	
	--by program
	SELECT '15' as 'IndicatorID'
	, h.EntityDesc as 'Facility'
	, h.ProgramDesc as 'Program'
	, h.FiscalPeriodEndDate as 'TimeFrame'
	, h.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Acute Productive Hours per Patient Day' as 'IndicatorName'
	, SUM(h.ProdHrs) as 'Numerator'
	, SUM(ip.ActualCensusDays) as 'Denominator'
	, SUM(1.0*h.ProdHrs)/IIF(SUM(ip.ActualCensusDays)=0,NULL,SUM(ip.ActualCensusDays)) as 'Value' --NULL to stop division by 0 error
	, 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	, 1.0*SUM(h.BudgetHrs)/IIF(SUM(ip.BudgetedCensusDays)=0,NULL,SUM(ip.BudgetedCensusDays)) as 'Target'	--NULL to stop division by 0 error
	, 'FinanceMart-Custom' as 'DataSource'	--Balanced scorecard productive horus / finance inpatient days total
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	INTO #TNR_ID15
	FROM  #tnr_productiveHoursPRGM as h
	INNER JOIN #TNR_inpatientDaysPGRM as ip
	ON h.FiscalPeriodLong=ip.FiscalPeriodLong
	AND h.ProgramDesc=ip.ProgramDesc
	AND h.EntityDesc=ip.EntityDesc
	WHERE h.EntityDesc in ('Richmond Health Services')	--excludes other regions for now but they are un the underlying tables
	GROUP BY h.EntityDesc
	, h.ProgramDesc
	, h.FiscalPeriodEndDate
	, h.FiscalPeriodLong
	--add overall
	UNION
	SELECT '15' as 'IndicatorID'
	, h.EntityDesc as 'Facility'
	, 'Overall' as 'Program'
	, h.FiscalPeriodEndDate as 'TimeFrame'
	, h.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Acute Productive Hours per Patient Day' as 'IndicatorName'
	, SUM(h.ProdHrs) as 'Numerator'
	, SUM(ip.ActualCensusDays) as 'Denominator'
	, SUM(1.0*h.ProdHrs)/IIF(SUM(ip.ActualCensusDays)=0,NULL,SUM(ip.ActualCensusDays)) as 'Value'			--NULL to stop division by 0 error
	, 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	, 1.0*SUM(h.BudgetHrs)/IIF(SUM(ip.BudgetedCensusDays)=0,NULL,SUM(ip.BudgetedCensusDays)) as 'Target'	--NULL to stop division by 0 error
	, 'FinanceMart-Custom' as 'DataSource'	--Balanced scorecard productive horus / finance inpatient days total
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	FROM  #tnr_productiveHoursPRGM as h
	INNER JOIN #TNR_inpatientDaysPGRM as ip
	ON h.FiscalPeriodLong=ip.FiscalPeriodLong
	AND h.ProgramDesc=ip.ProgramDesc			--there si something wrong with the program overlap
	AND h.EntityDesc=ip.EntityDesc
	WHERE h.EntityDesc in ('Richmond Health Services')	--excludes other regions for now
	GROUP BY h.EntityDesc
	, h.FiscalPeriodEndDate
	, h.FiscalPeriodLong
	;

-----------------------------------------------
-- ID16 Percent of surgical Patients Treated Within Target Wait Time
-----------------------------------------------
	/*	Purpose: to compute the percentage of surgeries completed within the target wait time. Wailist for surgery to surgery performed.
		Author: Kaloupis Peter
		Co-author: Hans Aisake
		Date Created: 2016
		Date Modified: April 1, 2019
		Inclusions/Exclusions: 
		Comments:
	*/
	IF OBJECT_ID('tempdb.dbo.#TNR_excludeORCodes') IS NOT NULL DROP TABLE #TNR_excludeORCodes;
	GO

	CREATE TABLE #TNR_excludeORCodes	( codes int);
	GO

	INSERT INTO #TNR_excludeORCodes VALUES(11048),(12001),(12002),(12003),(12004),(12005),(12006),(12007)
		,(12008),(12009),(20135),(30007),(40018),(40033),(10161),(10163),(20123)
		,(20124),(40029),(20012),(20049),(20138),(40040)
		;
		GO

	--compute and store the indicators
	IF OBJECT_ID('tempdb.dbo.#TNR_ID16') IS NOT NULL DROP TABLE #TNR_ID16;
	GO

	SELECT 	'16' as 'IndicatorID'
	, O.facilityLongName as 'Facility'
	,  REPLACE(REPLACE( O.LoggedMainSurgeonSpecialty, CHAR(13), ''), CHAR(10), '') as 'LoggedMainsurgeonSpecialty'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, '% Surgical Patients Treated Within Target Wait Time' as 'IndicatorName'
	, sum(cast(O.ismeetingtarget as int)) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum(cast(O.ismeetingtarget as int))/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P1' as 'Format'
	, 0.85 as 'Target'
	, 'ORMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	INTO #TNR_ID16
	FROM ORMARt.[dbo].[vwRegionalORCompletedCase] as O
	INNER JOIN #TNR_FPReportTF as T
	ON O.SurgeryPerformedDate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate	--surgeries performed in thursday week. Personally, I'd be more interested in waits starting than completion perspectives.
	LEFT JOIN #TNR_excludeORCodes as C
	ON O.[LoggedSPRPx1Code]=C.codes		--only keep codes 		('11048','12001','12002','12003','12004','12005','12006','12007','12008','12009','20135','30007','40018','40033','10161','10163','20123','20124','40029','20012','20049','20138','40040')
	WHERE O.facilitylongname='richmond hospital'	--richmond only
	and O.IsScheduled = 1		--only include scheduled surgeries 
	and ORRoomCode in ('RH BC','RH PRIVGOV','RHOR1','RHOR2','RHOR3','RHOR4','RHOR5','RHOR6','RHOR7','RHOR8','RHPRIV')	--only include these OR room codes for Richmond
	AND C.Codes is NULL	--exclude these procedures
	AND O.LoggedMainSurgeonSpecialty is not null
	AND O.LoggedMainSurgeonSpecialty not in ('Cardiology','Psychiatry')
	group by O.facilityLongName
	, T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, REPLACE(REPLACE( LoggedMainSurgeonSpecialty, CHAR(13), ''), CHAR(10), '') 
	--add overall
	UNION
	SELECT 	'16' as 'IndicatorID'
	, O.facilityLongName as 'Facility'
	,  'Overall' as 'LoggedMainsurgeonSpecialty'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, '% Surgical Patients Treated Within Target Wait Time' as 'IndicatorName'
	, sum(cast(O.ismeetingtarget as int)) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum(cast(O.ismeetingtarget as int))/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P1' as 'Format'
	, 0.85 as 'Target'
	, 'ORMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	FROM ORMARt.[dbo].[vwRegionalORCompletedCase] as O
	INNER JOIN #TNR_FPReportTF as T
	ON O.SurgeryPerformedDate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate	--surgeries performed in thursday week. Personally, I'd be more interested in waits starting than completion perspectives.
	LEFT JOIN #TNR_excludeORCodes as C
	ON O.[LoggedSPRPx1Code]=C.codes		--only keep codes 		('11048','12001','12002','12003','12004','12005','12006','12007','12008','12009','20135','30007','40018','40033','10161','10163','20123','20124','40029','20012','20049','20138','40040')
	WHERE O.facilitylongname='richmond hospital'	--richmond only
	and O.IsScheduled = 1		--only include scheduled surgeries 
	and ORRoomCode in ('RH BC','RH PRIVGOV','RHOR1','RHOR2','RHOR3','RHOR4','RHOR5','RHOR6','RHOR7','RHOR8','RHPRIV')	--only include these OR room codes for Richmond
	AND C.Codes is NULL	--exclude these procedures
	group by O.facilityLongName
	, T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	;
	GO

-----------------------------------------------
-- ID17 Direct Discharges From ED
-----------------------------------------------
	/*	Purpose: to compute how many DDFEs we have every week
		Author: Hans Aisake
		Date Created: 2017
		Date Modified: April 1, 2019
		Inclusions/Exclusions: 
		Comments:
	*/
	IF OBJECT_ID('tempdb.dbo.#TNR_ID17') IS NOT NULL DROP TABLE #TNR_ID17;
	GO

	SELECT 	'17' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, T.FiscalPeriodEndDate as 'TimeFrame'
	, T.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'timeFrameType'
	, '# Direct Discharges from ED' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, Count(distinct ED.VisitId)  as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	INTO #TNR_ID17
	FROM EDMART.[dbo].[vwEDVisitIdentifiedRegional] as ED
	INNER JOIN #TNR_FPReportTF as T
	ON ED.Dispositiondate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate		--link ED visit dispositions to thursday weeks and only keep those of interest in the reporting time frame
	WHERE ED.[InpatientNursingUnitName] ='Invalid'		--this is populated with invalid because there was a bed request but not proper inpatient unit was noted
	AND ED.facilityshortname='RHS'						--only richmond ED visits
	GROUP BY T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

	--append 0's for groups where no data was present but was expected
	INSERT INTO #TNR_ID17 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall, Scorecard_eligible, IndicatorCategory)
	SELECT 	'17' as 'IndicatorID'
	, p.facility
	, p.IndicatorName
	, P.Program
	, P.TimeFrame
	, P.TimeFrameLabel as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, 0 as 'Value'	--proper 0's
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, CASE WHEN P.Program ='Overall' THEN 1 ELSE 0 END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	FROM #placeholder as P
	LEFT JOIN #TNR_ID17 as I
	ON P.facility=I.Facility
	AND P.IndicatorId=I.IndicatorID
	AND P.Program=I.Program
	AND P.TimeFrame=I.TimeFrame
	WHERE P.IndicatorID= (SELECT distinct indicatorID FROM #TNR_ID17)
	AND I.[Value] is NULL
	;
	GO

-----------------------------------------------
--ID19 Short Stay discahrges (<=48hrs) excludes Newborns
-----------------------------------------------
	/*
	Purpose: To compute how many people are discahrged within 48hrs of admission
	Author: Hans Aisake
	Date Created: June 14, 2018
	Date Updated: April 1, 2019
	Inclusions/Exclusions:
		- true inpatient records only
		- excludes newborns
	Comments:
	*/

	IF OBJECT_ID('tempdb.dbo.#TNR_SSad_18') IS NOT NULL DROP TABLE #TNR_SSad_18;
	GO

	SELECT T.fiscalPeriodLong
	, T.FiscalPeriodEndDate
	, DischargeFacilityLongName
	, CASE WHEN datediff(mi,ADTC.[AdjustedAdmissionDate]+ADTC.[AdjustedAdmissionTime],ADTC.[AdjustedDischargeDate]+ADTC.[AdjustedDischargeTime]) between 0 and 1440 THEN '<=24 hrs'
			WHEN datediff(mi,ADTC.[AdjustedAdmissionDate]+ADTC.[AdjustedAdmissionTime],ADTC.[AdjustedDischargeDate]+ADTC.[AdjustedDischargeTime]) between 1441 and 2160 THEN '24 to 36 hrs'
			WHEN datediff(mi,ADTC.[AdjustedAdmissionDate]+ADTC.[AdjustedAdmissionTime],ADTC.[AdjustedDischargeDate]+ADTC.[AdjustedDischargeTime]) between 2161 and 2880 THEN '36 to 48 hrs'
			ELSE '>48 hrs' 
	END as 'LOSRange'
	, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
	, 1 as casecount
	INTO #TNR_SSad_18
	FROM ADTCMart.[ADTC].[vwAdmissionDischargeFact] as ADTC
	INNER JOIN #TNR_FPReportTF as T				
	on ADTC.[AdjustedDischargeDate] BETWEEN T.FiscalPeriodStartDate AND  T.FiscalPeriodEndDate	--only discharges in reporting time frame
	LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP		--a map of nursing unit to program; not maintained by dmr
	ON ADTC.DischargeNursingUnitCode=MAP.NursingUnitCode		--same code
	AND ADTC.AdjustedDischargeDate BETWEEN MAP.StartDate AND MAP.EndDate	--within the active dates
	WHERE [DischargeFacilityLongName]='Richmond Hospital'	--only richmond
	AND DischargeNursingUnitDesc not in ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')	--exclude Minoru 
	AND [AdjustedDischargeDate] is not null		--discharges only
	AND [DischargePatientServiceCode]<>'NB'		--exclude newborns
	AND [AccountType]='I'						--inpatient cases only
	AND [AdmissionAccountSubType]='Acute'		--inpatient subtype
	;
	GO

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID18') IS NOT NULL DROP TABLE #TNR_ID18;
	GO

	SELECT 	'18' as 'IndicatorID'
	, DischargeFacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Short Stay Discharges (LOS<=48hrs)' as 'IndicatorName'
	,sum(CASE WHEN losrange<>'>48 hrs' THEN 1 else 0 end) as 'Numerator'
	,count(*) as 'Denominator'
	, 1.0*sum(CASE WHEN losrange<>'>48 hrs' THEN 1 else 0 end)/count(*) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P0' as 'Format'
	,  0.25 as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	INTO #TNR_ID18
	FROM #TNR_SSad_18
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, DischargeFacilityLongName
	, Program
	--add overall
	UNION
	SELECT 	'18' as 'IndicatorID'
	, DischargeFacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Short Stay Discharges (LOS<=48hrs)' as 'IndicatorName'
	, sum(case WHEN losrange<>'>48 hrs' THEN 1 else 0 end) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*sum(case WHEN losrange<>'>48 hrs' THEN 1 else 0 end)/count(*) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P0' as 'Format'
	,  0.25 as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	FROM #TNR_SSad_18
	GROUP BY FiscalPeriodLong
	, fiscalPeriodEndDate
	, DischargeFacilityLongName
	;
	GO

--------------------------------
--- Consolidate Indicators
-------------------------------
	--clear out the old data values
	TRUNCATE TABLE DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS;
	GO

	--put the new data into the table
	INSERT INTO DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS (IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory)
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID01
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID01
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID02
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID03
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID04
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID05
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID06
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID07
	--UNION
	--SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	--FROM #TNR_ID08
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID09
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID10
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID11
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID12
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID13
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID14
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID15
	UNION
	SELECT IndicatorID, Facility, LoggedMainsurgeonSpecialty, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID16
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID17
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory
	FROM #TNR_ID18
	--add fake rows to populate summary page
	UNION
	SELECT TOP 1 '08', 'Richmond Hospital', 'Overall', '2020-05-02','2020-01','Fiscal Period','Discharges actual vs. predicted', NULL,NULL, NULL, 'Above','D1',NULL,'Placeholder',1,1, 'Exceptional Care'
	FROM #TNR_ID01
	;
	GO
	
	--most recent values
	--IF OBJECT_ID('tempdb.dbo.#mostRecent') is not null DROP TABLE #mostRecent;
	--GO

	--SELECT IndicatorName
	--, Program
	--, MAX(timeframe) as 'LatestTimeFrame'
	--INTO #mostRecent
	--FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS
	--WHERE indicatorID !=16
	--OR (indicatorID=16 AND program='Overall')
	--GROUP BY IndicatorName
	--, Program
	--;

	--SELECT X.*
	--FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS as X
	--INNER JOIN #mostRecent as Y
	--ON  X.TimeFrame=Y.LatestTimeFrame
	--AND X.Program=Y.Program
	--AND X.IndicatorName=Y.IndicatorName
	--OR  X.indicatorID in ('08')
	--WHERE X.Program not in ('Unknown')
	----ORDER BY IndicatorID ASC, TimeFrame DESC



------------
-- END QUERY
------------

--Discontinued indicators

-------------------------------------------------
---- MRSA/CDI/CPO Rate/Rate/Case per 10,000/10,000/Raw Patient Days ID04
-------------------------------------------------
--	/*
--	Purpose: Takes the existing weekly MRSA/CDI data query and aggregates the data to fiscal periods instead of by week.
--	Then over writes old periods with existing official data.
--	Official and unofficial data are flagged via Data Type.
--	The table can then be used to generate an SSRS chart in the visibility wall report.

--	Author: Hans Aisake
--	Co-author: Peter Kaloupis
--	Date Create: January 25, 2017
--	Date Modified: April 1, 2019
--	Inclusions/exclusions: excludes TCU census days. only includes inpatient census days
--	Comments: This metric needs to be recast in a longer time frame like Fiscal Quarter, but better yet revampped to be time between cases with T or G chart based definitions due to these events being so rare.
--    T or G charts would require different data feeds.
--	*/
		
--	--------------------------------------------------
--	--	Reporting Periods
--	--------------------------------------------------
--	--find reporting periods current fiscal period and the last 3 fiscal years for the weekly date
--	IF OBJECT_ID('tempdb.dbo.#TNR_HAI_tf') IS NOT NULL DROP TABLE #TNR_HAI_tf;
--	GO
	
--	SELECT distinct TOP 36 fiscalperiodlong, fiscalperiodstartdate, fiscalperiodenddate
--	INTO #TNR_HAI_tf
--	FROM ADRMart.dim.[Date]
--	WHERE FiscalPeriodLong <= (select max([Period]) from DSSI.[dbo].[RHMRSACDIPeriodVisibilityWall])
--	ORDER BY fiscalperiodlong DESC
--	;
--	GO

--	--------------------------------------------------
--	--	results data structure to ensure 0 counts; might not have appropriate histoy cutoffs
--	--------------------------------------------------
--	IF OBJECT_ID('tempdb.dbo.#TNR_HAI') IS NOT NULL DROP TABLE #TNR_HAI;
--	GO

--	SELECT DISTINCT D.FiscalPeriodLong
--	, D.FiscalPeriodStartDate
--	, D.FiscalPeriodEndDate
--	, P.Program 
--	, I.infection
--	INTO #TNR_HAI
--	FROM #TNR_HAI_tf as D
--	CROSS JOIN (SELECT DISTINCT [NewProgram] as 'Program' FROM DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] WHERE HAI_unitName is not NULL) as P		--only units that showed up in the MRSA/CDI weekly data or the official data are included in the mapping. new units must be added
--	CROSS JOIN (SELECT 'CDI' as 'Infection') as I
--	;
--	GO

--	--------------------------------------------------
--	--Compute IP census
--	--------------------------------------------------
--	--TCU Census: date and account number for exclusion
--	IF OBJECT_ID('tempdb.dbo.#TNR_TCU_census') IS NOT NULL DROP TABLE #TNR_TCU_census;
--	GO

--	SELECT censusDate, AccountNum, [site]
--	INTO #TNR_TCU_census
--	FROM adtcmart.[ADTC].[vwCensusFact]
--	WHERE [site]='rmd' AND [AccountType]='Inpatient' AND
--	(  ([AccountSubType]='Extended' and [NursingUnitCode]='R3N' and censusdate <='2018-08-24')
--			OR ([AccountSubType]='Extended' and [NursingUnitCode]='R4N' and censusdate BETWEEN '2018-08-25' AND '2018-10-17')
--			OR ([AccountSubType]='Extended' and [NursingUnitCode]='R3S')
--			OR [PatientServiceCode]='TC'
--			)
--	;
--	GO

--	--pull census days
--	IF OBJECT_ID('tempdb.dbo.#TNR_HAI_census') IS NOT NULL DROP TABLE #TNR_HAI_census;
--	GO
	
--	SELECT D.FiscalPeriodLong
--	, CASE WHEN M.NewProgram is NULL THEN 'UNKNOWN' ELSE m.NewProgram END as 'Program'
--	, COUNT(1) as 'NumIPDays'
--	INTO #TNR_HAI_census
--	FROM adtcmart.[ADTC].[vwCensusFact] as C
--	INNER JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC]  as M
--	ON C.[NursingUnitCode]=M.[NursingUnitCode]	--only pull census for mapped units
--	LEFT JOIN #TNR_HAI_tf as D
--	ON C.CensusDate BETWEEN D.FiscalPeriodStartDate AND D.FiscalPeriodEndDate
--	WHERE C.[FacilityLongName]='richmond hospital'	--Richmond only
--	AND C.nursingunitdesc not in ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')	--exclude Minoru 
--	AND C.[AccountType]='Inpatient'	--inpatients only
--	AND not exists (SELECT 1 FROM #TNR_TCU_census as TCU WHERE TCU.AccountNum=C.AccountNum AND TCU.CensusDate=C.CensusDate AND TCU.[site]=C.[site])	--exclude TCU
--	GROUP BY D.FiscalPeriodLong, CASE WHEN M.NewProgram is NULL THEN 'UNKNOWN' ELSE m.NewProgram END
--	;
--	GO
	
--	--------------------------------------------------
--	--Compute # of official cases by infection and nursing unit
--	--------------------------------------------------
--	IF OBJECT_ID('tempdb.dbo.#TNR_HAI_officialcases') IS NOT NULL DROP TABLE #TNR_HAI_officialcases;
--	GO
	
--	SELECT I.[Period] as 'FiscalPeriodLong'
--	, I.infection
--	, CASE WHEN M.NewProgram is NULL THEN 'UNKNOWN' ELSE m.NewProgram END as 'Program'
--	, SUM(cases) as 'NumCases'
--	INTO #TNR_HAI_officialcases
--	FROM DSSI.dbo.RHMRSACDIPeriodVisibilityWall as I
--	LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC]  as M
--	ON I.NursingUnitCode=M.NursingUnitCode
--	GROUP BY I.[Period]
--	, I.infection
--	, CASE WHEN M.NewProgram is NULL THEN 'UNKNOWN' ELSE m.NewProgram END
--	;
--	GO
	
--	--------------------------------------------------
--	--Combine all the results together
--	--------------------------------------------------
--	IF OBJECT_ID('tempdb.dbo.#TNR_ID04') IS NOT NULL DROP TABLE #TNR_ID04;
--	GO

--	SELECT '4' as 'IndicatorID'
--	, 'Richmond Hospital' as 'Facility'
--	, X.Infection
--	, X.Program
--	, X.FiscalPeriodEndDate as 'TimeFrame'
--	, X.FiscalPeriodLong as 'TimeFrameLabel'
--	, 'Fiscal Period' as 'TimeFrameType'
--	, X.Infection + ' Rate per 10,000 Patient Days' as 'IndicatorName'
--	, ISNULL(O.NumCases,0) as 'Numerator'
--	, C.NumIPDays as 'Denominator'
--	, 10000.0*ISNULL(O.NumCases,0) / C.NumIPDays as 'Value'
--	, 'Below' as 'DesiredDirection'
--	, 'D1' as 'Format'
--	,  CASE WHEN X.infection='CDI' AND X.fiscalperiodlong<='2016-09' THEN 7.5
--			WHEN X.infection='CDI' AND X.fiscalperiodlong >='2016-10' THEN 7.33
--			ELSE NULL
--	END as 'Target'
--	, 'QPS' as 'DataSource'
--	, 0 as 'IsOverall'
--	, 1 as 'Scorecard_eligible'
--	INTO #TNR_ID04
--	FROM #TNR_HAI as X
--	LEFT JOIN #TNR_HAI_officialcases as O
--	ON X.FiscalPeriodLong=O.FiscalPeriodLong AND X.Program=O.Program AND X.Infection=O.Infection
--	LEFT JOIN #TNR_HAI_census as C
--	ON X.FiscalPeriodLong=C.FiscalPeriodLong AND X.Program=C.Program
--	--add overall
--	UNION
--	SELECT '4' as 'IndicatorID'
--	, 'Richmond Hospital' as 'Facility'
--	, X.Infection
--	, 'Overall' as 'Program'
--	, X.FiscalPeriodEndDate as 'TimeFrame'
--	, X.FiscalPeriodLong as 'TimeFrameLabel'
--	, 'Fiscal Period' as 'TimeFrameType'
--	, X.Infection + ' Rate per 10,000 Patient Days' as 'IndicatorName'
--	, SUM( ISNULL(O.NumCases,0)) as 'Numerator'
--	, SUM(C.NumIPDays) as 'Denominator'
--	, 10000.0*SUM(ISNULL(O.NumCases,0))/ SUM(C.NumIPDays) as 'Value'
--	, 'Below' as 'DesiredDirection'
--	, 'D1' as 'Format'
--	,  CASE WHEN X.infection='CDI' AND X.fiscalperiodlong<='2016-09' THEN 7.5
--			WHEN X.infection='CDI' AND X.fiscalperiodlong >='2016-10' THEN 7.33
--			WHEN X.infection='CPO' THEN NULL	--no known target
--			ELSE NULL
--	END as 'Target'
--	, 'QPS' as 'DataSource'
--	, 1 as 'IsOverall'
--	, 1 as 'Scorecard_eligible'
--	FROM #TNR_HAI as X
--	LEFT JOIN #TNR_HAI_officialcases as O
--	ON X.FiscalPeriodLong=O.FiscalPeriodLong AND X.Program=O.Program AND X.Infection=O.Infection
--	LEFT JOIN #TNR_HAI_census as C
--	ON X.FiscalPeriodLong=C.FiscalPeriodLong AND X.Program=C.Program
--	GROUP BY X.Infection, X.FiscalPeriodLong, X.FiscalPeriodEndDate
--	;
--	GO


--	DELETE FROM #TNR_ID04 WHERE Program ='Mental Health & Addictions Ser';
--	GO
