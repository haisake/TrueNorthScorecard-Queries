/*
Purpose: To create a consolidated query that constructs the indciators for the true north richmond scorecard and the richmond true north metrics
Author: Hans Aisake
Date Created: April 1, 2019
Date Modified: August 21, 2019
Inclusions/Exclusions:
Comments:

Why do we remove Mental Health from the ALOS indicator?

DSSI.dbo.RollingFiscalYear

*/ 

------------------------
--Indentify true inpatient units
------------------------
	----this Misses richmond TCU patients because they can't be identified by unit
	--IF OBJECT_ID('tempdb.dbo.#adtcNUClassification_tnr') IS NOT NULL DROP TABLE #adtcNUClassification_tnr;
	--GO

	--SELECT * INTO #adtcNUClassification_tnr FROM [DSSI].[dbo].[vwNULevels];
	--GO

-----------------------------------------------
--Reporting TimeFrames
-----------------------------------------------

	--distinct reporting periods based on 1 day lag for ADTC update consideration
	IF OBJECT_ID('tempdb.dbo.#tnr_periods') IS NOT NULL DROP TABLE #tnr_periods;
	GO

	SELECT distinct TOP 53 FiscalPeriodLong, fiscalperiodstartdate, fiscalperiodenddate, FiscalPeriodEndDateID, FiscalPeriod, FiscalYearLong, FiscalYear, DATEDIFF(Day, fiscalperiodstartdate, fiscalperiodenddate) +1 as 'days_in_fp'
	INTO #tnr_periods
	FROM ADTCMart.dim.[Date]
	WHERE fiscalperiodenddate <= DATEADD(day, -1, GETDATE())
	ORDER BY FiscalPeriodEndDate DESC
	;
	GO
	
	--last 3 years, including current years, fiscal periods
	IF OBJECT_ID('tempdb.dbo.#TNR_FPReportTF') IS NOT NULL DROP TABLE #TNR_FPReportTF;
	GO

	SELECT * 
	INTO #TNR_FPReportTF
	FROM #tnr_periods
	WHERE fiscalYearLong in (	SELECT distinct TOP 3  FiscalYearLong FROM #tnr_periods ORDER BY FiscalYearLong DESC )
	;
	GO

	-- find latest 3 rolling fiscal years
	IF OBJECT_ID('tempdb.dbo.#TNR_RFY_ReportTF') IS NOT NULL DROP TABLE #TNR_RFY_ReportTF;
	GO

	SELECT TOP 39 *
	INTO #TNR_RFY_ReportTF
	FROM DSSI.dbo.RollingFiscalYear
	WHERE [End_RFY_Date] <= DATEADD(day, -1, GETDATE())
	;
	GO

---------------------------------------------------
--Finance Data from the General Ledger - April 2019
---------------------------------------------------
	
	-------------------
	-- Inpatient Days
	-------------------
		--we mostly need an inpatient days definition for indicators 6, 12, 14, and the ALOS
		--different sources are used for all these indicators with different criteria for different reports....
		--I'm syncronizing this report to a single inpatient days number for each period
		--what mapping we use can change as we go, but here I get everything by cost center for all inpatient days accounts
		--Depending on who you ask not all of '%S403%' is appropriate. There are newborn related days.
		-- Richmonds stat acountsare S403105, S403107, S403145, S403410, & S403430 which correspond to
		-- Inpatient Days-Acute, Inpatient Days-Sub Acute, Inpatient Days-Infant respectively, Inpatient Days - Newborn, Inpatient Days ICU Nursery respectively

		--gets the inpatient days from financemart the same was as for HPPD; uses the default program mapping in financemart
		IF OBJECT_ID('tempdb.dbo.#tnr_inpatientDaysByCC') is not null DROP TABLE #tnr_inpatientDaysByCC;
		GO

		SELECT D.FiscalYearLong, D.FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodStartDate, D.FiscalPeriodEndDate,  cc.CostCenterCode, cc.CostCenterDesc, ledger.FinSiteID, P.EntityDesc
		, ledger.GLAccountCode
		, ISNULL(sum(ledger.BudgetAmt), 0.00) as 'BudgetedCensusDays'	--historical periods don't have values recorded so they are 0. Future records are not actually 0 untill some date. This is because the budget extends into the future
		, ISNULL(sum(ledger.ActualAmt),0.00) as 'ActualCensusDays'		--historical periods don't have values recorded so they are 0 Future records are not actually 0 untill some date. This is because the budget extends into the future
		INTO #tnr_inpatientDaysByCC
		FROM FinanceMart.Finance.GLAccountStatsFact as ledger
		LEFT JOIN FinanceMart.dim.CostCenter as CC
		ON ledger.CostCenterID=CC.CostCenterID
		LEFT JOIN FinanceMart.finance.EntityProgramSubProgram as P		--get the entity of the cost center fin site id
		ON ledger.[CostCenterBusinessUnitEntitySiteID]=P.[CostCenterBusinessUnitEntitySiteID]
		INNER JOIN #TNR_FPReportTF as D					--only fiscal year/period we want to report on as defined in #hppd_fp
		ON ledger.FiscalPeriodEndDateID=d.FiscalPeriodEndDateID	--same fiscal period and year
		WHERE (ledger.GLAccountCode like '%S403%')	--S403 is all inpatient day accounts this includes the new born accounts. S404 is for residential care days and used in the BSc, but it doens't catch any thing. The BSC inpatient days excludes 'S403410','S403430' which are IP accounts for Inpatient Days - Newborn, Inpatient Days ICU Nursery respectively
		GROUP BY D.FiscalYearLong, D.FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodStartDate, D.FiscalPeriodEndDate,  cc.CostCenterCode, cc.CostCenterDesc, ledger.FinSiteID, P.EntityDesc, ledger.GLAccountCode
		GO


		--compute and store indicators
		IF OBJECT_ID('tempdb.dbo.#TNR_inpatientDaysPGRM') IS NOT NULL DROP TABLE #TNR_inpatientDaysPGRM;
		GO

		SELECT X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, Y.ProgramDesc
		, SUM( CASE WHEN Y.ProgramDesc like '%Pop%' THEN BudgetedCensusDays
					WHEN X.GLAccountCode in ('S403105', 'S403107', 'S403145') THEN BudgetedCEnsusDays
					ELSE 0
				END
		) as 'BudgetedCensusDays'
		, SUM( CASE WHEN Y.ProgramDesc like '%Pop%' THEN ActualCensusDays
					WHEN X.GLAccountCode in ('S403105', 'S403107', 'S403145') THEN ActualCensusDays
					ELSE 0
				END
		) as 'ActualCensusDays'
		INTO #TNR_inpatientDaysPGRM
		FROM #tnr_inpatientDaysByCC as X
		INNER JOIN FinanceMart.Finance.EntityProgramSubProgram as Y
		ON X.FinSiteID=Y.FinSiteID
		AND X.CostCenterCode =Y.CostCenterCode
		AND Y.ProgramDesc is not NULL
			GROUP BY X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, Y.ProgramDesc
		UNION
		SELECT X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, 'Overall' as 'ProgramDesc'
		, SUM( BudgetedCensusDays) as 'BudgetedCensusDays'
		, SUM( ActualCensusDays) as 'ActualCensusDays'
		FROM #tnr_inpatientDaysByCC as X
		INNER JOIN FinanceMart.Finance.EntityProgramSubProgram as Y
		ON X.FinSiteID=Y.FinSiteID
		AND X.CostCenterCode =Y.CostCenterCode
		AND Y.ProgramDesc is not NULL
		WHERE X.GLAccountCode in ('S403105', 'S403107', 'S403145')	--exclude the NICU/SCN days
		GROUP BY X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		;
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
	-- add overall
		UNION
		SELECT [hours].FiscalYearLong, [hours].FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodEndDate, P.EntityDesc, 'Overall' as 'ProgramDesc'
		--, f.FinSiteCode, f.CostCenterCode
		--, cc.CostCenterDesc
		, SUM(ActualHrs) as 'ProdHrs' 
		, SUM(BudgetHrs) as 'BudgetHrs'
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
		GROUP BY [hours].FiscalYearLong, [hours].FiscalPeriod, D.FiscalPeriodLong, D.FiscalPeriodEndDate, P.EntityDesc
		;
		GO
	------------------

---------------------------------------------------
--identify all possible indicator week combinations
---------------------------------------------------
	--only works if the data has be populated earlier; for intial runs this section probably needs to be skipped or worked around.
	--the idea is the data itself tells us what periods it has first and last, we can then fill in gaps with 0s
	IF OBJECT_ID('tempdb.dbo.#placeholder') IS NOT NULL DROP TABLE #placeholder;
	GO

	SELECT * 
	INTO #placeholder
	FROM 
	(SELECT distinct FiscalPeriodLong as 'TimeFrameLabel', FiscalPeriodEndDate as 'timeFrame' , fiscalperiodstartdate FROM #TNR_FPReportTF) as X
	CROSS JOIN 
	(	SELECT distinct  Facility, indicatorId, indicatorname, program 
		FROM DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS]
		WHERE indicatorId in ('05','06','17')	-- where the indicator is likley to have a true 0
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
	Date Updated: Oct 4, 2019
	Inclusions/Exclusions:
	Comments:
		Unkown program is when patients are admitted but they never arrive at an inpatient unit and become DDFEs.
		It is included in the overall, but cannot be allocated to any program.

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
		AND not exists (SELECT 1 FROM EDMart.dbo.vwDTUDischargedHome as Z WHERE ED.continuumID=Z.ContinuumID)	--exclude clients discharged home from the DTU ; part of indicator definition
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
	, '% ED Visits' as 'Units'
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
	, '% ED Visits' as 'Units'
	FROM #TNR_ed01
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

	--remove these programs 
	DELETE FROM #TNR_ID01 
	WHERE Program in ('Long Term Care Services')
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
		Unkown program is when patients are admitted but they never arrive at an inpatient unit and become DDFEs.
		It is included in the overall, but cannot be allocated to any program.
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
		AND not exists (SELECT 1 FROM EDMart.dbo.vwDTUDischargedHome as Z WHERE ED.continuumID=Z.ContinuumID)	--exclude clients discharged home from the DTU; part of indicator definition
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
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  CAST(NULL as float) as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '% ED Visits' as 'Units'
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
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  CAST(NULL as float) as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '% ED Visits' as 'Units'
	FROM #TNR_ed02
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

	--set targets AVG of last 3 FY; new addition for richmond
	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID02_targets') IS NOT NULL DROP TABLE #TNR_ID02_targets;
	GO

	SELECT X.TimeFrameLabel
	, X.Facility
	, X.Program
	, Ceiling(1000*AVG( Y.[Value] ))/1000.0 +0.001 as 'Target' 
	INTO #TNR_ID02_targets
	FROM #TNR_ID02 as X
	LEFT JOIN #TNR_ID02 as Y
	ON  CAST( LEFT(Y.TimeFrameLabel,4)  as int) -1 BETWEEN CAST( LEFT(X.TimeFrameLabel,4) as int)-2 AND CAST( LEFT(X.TimeFrameLabel,4) as int)	--last 3 fiscal years not including current
	AND RIGHT(X.TimeFrameLabel,2)=RIGHT(Y.TimeFrameLabel,2)	--same period
	AND X.Facility=Y.Facility	--same site
	AND X.Program=Y.Program	--same program
	GROUP BY X.TimeFrameLabel
	, X.Facility
	, X.Program

	--add targets to the table
	UPDATE X
	SET X.[Target] = Y.[Target]
	FROM #TNR_ID02 as X INNER JOIN #TNR_ID02_targets as Y
	ON X.Facility=Y.Facility
	AND X.Program=Y.Program
	AND X.TimeFrameLAbel=Y.TimeFrameLabel
	WHERE Y.[Target] is not null
	;
	GO

	--remove Minoru indicators
	DELETE FROM #TNR_ID02
	WHERE Program in ('Long Term Care Services')
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
		Unkown program is when patients are admitted but they never arrive at an inpatient unit and become DDFEs.
		It is included in the overall, but cannot be allocated to any program.
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
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  CAST(NULL as float) as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '% ED Visits' as 'Units'
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
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	,  CAST(NULL as float) as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '% ED Visits' as 'Units'
	FROM #TNR_ed03
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,FacilityLongName
	;
	GO

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID03_targets') IS NOT NULL DROP TABLE #TNR_ID03_targets;
	GO

	SELECT X.TimeFrameLabel
	, X.Facility
	, X.Program
	, Ceiling(1000*AVG( Y.[Value] ))/1000.0 +0.001 as 'Target' 
	INTO #TNR_ID03_targets
	FROM #TNR_ID03 as X
	LEFT JOIN #TNR_ID03 as Y
	ON  CAST( LEFT(Y.TimeFrameLabel,4)  as int) -1 BETWEEN CAST( LEFT(X.TimeFrameLabel,4) as int)-2 AND CAST( LEFT(X.TimeFrameLabel,4) as int)	--last 3 fiscal years not including current
	AND RIGHT(X.TimeFrameLabel,2)=RIGHT(Y.TimeFrameLabel,2)	--same period
	AND X.Facility=Y.Facility	--same site
	AND X.Program=Y.Program	--same program
	GROUP BY X.TimeFrameLabel
	, X.Facility
	, X.Program
	;
	GO

	--add targets to the table
	UPDATE X
	SET X.[Target] = Y.[Target]
	FROM #TNR_ID03 as X INNER JOIN #TNR_ID02_targets as Y
	ON X.Facility=Y.Facility
	AND X.Program=Y.Program
	AND X.TimeFrameLAbel=Y.TimeFrameLabel
	WHERE Y.[Target] is not null
	;
	GO

	--remove Minoru indicators
	DELETE FROM #TNR_ID03
	WHERE Program in ('Long Term Care Services')
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
	, Budget
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
	,  Budget as 'Target'
	, 'FinaceMart-ALOS Periodic Report' as 'DataSource'
	, CASE WHEN Program = 'Overall' THEN 1
		   ELSE 0
	END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, 'Days' as 'Units'
	INTO #TNR_ID04
	FROM #TNR_financeALOS_04
	WHERE program not in ('RHS COO Unallocated','Long Term Care Services')
	--overall is included in the source data and doesn't need to be added here like the other indicators
	;
	GO

	--workaround to get targets
	IF OBJECT_ID('tempdb.dbo.#TNR_ID04_targets') IS NOT NULL DROP TABLE #TNR_ID04_targets;
	GO

	SELECT  F.FiscalYear
	, D.FiscalPeriodEndDate		--get the fiscal period date from another table
	, CASE	WHEN sector='' AND program='' AND subprogram ='' AND costcenter ='' THEN 'Overall'	--rename the overall label to be consistent with other indicators
			WHEN Program in ('Critical Care-Med-Pat Flow','Emergency-CC & Medicine') THEN 'Emerg & Critical Care'	--fix the old names to the new names
			WHEN Program = 'Home & Community Care' THEN 'Home & Community Care'
			WHEN Program = 'Med Adm-Surg-Ambl' THEN 'Surgery & Procedural Care'
			WHEN Program = 'Mental Health & Addictions Ser' THEN  'Mental Hlth & Substance Use'
			WHEN Program = 'Overall' THEN 'Overall'
			WHEN Program = 'Population & Family Health' THEN 'Pop & Family Hlth & Primary Cr'
			WHEN Program = 'Residential Care Services' THEN 'Long Term Care Services'
			ELSE Program
	END as 'Program'
	, 'Richmond Hospital' as 'Facility'
	, LOS as 'Inpatient_Days'					--this inptient days is different from waht I computed in the other indicators
	, Visits as 'Visits'
	, IIF(visits is null OR visits =0, null, 1.0*LOS/Visits) as 'ALOS'
	, Budget as 'Target'
	INTO #TNR_ID04_targets
	FROM [FinanceMart].[LOS].[ALOSBudget] as F
	INNER JOIN #TNR_FPReportTF as D		
	ON F.FiscalYear=D.FiscalYearLong		--only periods of interest in the report
	where RptGrouping = 'Entity'	--program groupings
	AND entity =  'Richmond Health Services'	--richmond only
	AND subprogram =''							--don't want program breakdowns
	AND F.Visits !=0	--ignore records with 0 visits
	;
	GO

	--add targets; year target to all periods
	UPDATE X 
	SET [Target] = Y.[Target]
	FROM #TNR_ID04 as X
	INNER JOIN #TNR_ID04_targets as Y
	ON LEFT(X.TimeFrameLabel,4) = Y.FiscalYear	--same fiscal year
	AND X.FAcility=Y.Facility	--same facility
	AND X.Program=Y.Program	--same program
	WHERE X.[Target] is null --target from the period end report not found; given report grouping by director
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

		It looks like the BSC numbers exclude MH from the total
	
	*/
	-------------------
	--pull LLOS (>30 days) census data for patients 
	------------------
	IF OBJECT_ID('tempdb.dbo.#TNR_LLOS_data') IS NOT NULL DROP TABLE #TNR_LLOS_data;
	GO

	SELECT  
	CASE WHEN ADTC.AdmittoCensusDays > 210 THEN 180
		 WHEN ADTC.AdmitToCensusDays BETWEEN 31 AND 210 THEN ADTC.AdmittoCensusDays-30 
		 ELSE 0
	END as 'LLOSDays'
	,CASE	WHEN ADTC.AdmitToCensusDays > 30 THEN ADTC.PatientID	--redundant
			ELSE NULL
	END as 'LLOS_PatientID'
	, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
	, D.FiscalPeriodLong
	, D.FiscalPeriodEndDate
	, ADTC.FacilityLongName
	, ADTC.PatientId
	, ADTC.PatientServiceDescription
	, ADTC.PatientServiceCode
	INTO #TNR_LLOS_data
	FROM ADTCMart.[ADTC].[vwCensusFact] as ADTC
	INNER JOIN #TNR_FPReportTF as D 
	ON ADTC.CensusDate =D.FiscalPeriodEndDate	--pull census for the fiscal period end, as a snapshot
	--INNER JOIN #adtcNUClassification_tnr as NU
	--ON ADTC.NursingUnitCode=NU.NursingUnitCode					--match on nursing unit
	--AND NU.NULevel='Acute'										--only inpatient units
	LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP		--get program
	ON ADTC.NursingUnitCode=MAP.nursingunitcode					--match on nursing unit
	AND ADTC.CensusDate BETWEEN MAP.StartDate AND MAP.EndDate	--active program unit mapping dates
	WHERE ADTC.age>1				--P4P standard definition to exclude newborns.
	AND ADTC.AdmittoCensusDays > 30	--only need the LLOS patients, I'm not interested in proportion of all clients
	AND (ADTC.HealthAuthorityName = 'Vancouver Coastal' -- only include residents of Vancouver Coastal
	OR (ADTC.HealthAuthorityName = 'Unknown BC' AND (ADTC.IsHomeless = '1' OR ADTC.IsHomeless_PHC = '1'))) -- Include Unknown BC homeless population
	AND ADTC.[Site] ='rmd'									--only include census at Richmond
	AND LEFT(ADTC.NursingUnitCode,1)!='M'	--excludes ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')
	AND ADTC.AccountType in ('I', 'Inpatient', '391')		--the code is different for each facility. Richmond is Inpatient
	AND ADTC.AccountSubtype in ('Acute')					--the true inpatient classification is different for each site. This is the best guess for Richmond
	--AND ADTC.PatientServiceCode not in ('TC','EC')			--exclude transitional care and extended care census days
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
	, COUNT(distinct LLOS_PatientID) as 'Value'
	 , 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '# Patients' as 'Units'
	INTO #TNR_ID05
	FROM #TNR_LLOS_data
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
	, COUNT(distinct LLOS_PatientID) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '# Patients' as 'Units'
	FROM #TNR_LLOS_data
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

	--append 0's ; might be something wrong here
	INSERT INTO #TNR_ID05 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall,Scorecard_eligible, IndicatorCategory, Units)
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
	, CAST(NULL as float) as 'Target'
	, 'ADTCMart' as 'DataSource'
	, CASE WHEN P.Program ='Overall' THEN 1 ELSE 0 END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '# Patients' as 'Units'
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

	--set targets AVG of last 3 FY; TNSC 201904-08_TNS.Targets.xksx
	--BSC says the same thing but the definition iplies for the same YTD time range, so in this case it would be last 3 years same fiscal periods
	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID05_targets') IS NOT NULL DROP TABLE #TNR_ID05_targets;
	GO

	SELECT X.TimeFrameLabel
	, X.Facility
	, X.Program
	, AVG( Y.[Value] ) as 'Target'
	INTO #TNR_ID05_targets
	FROM #TNR_ID05 as X
	LEFT JOIN #TNR_ID05 as Y
	ON  CAST( LEFT(Y.TimeFrameLabel,4)  as int) -1 BETWEEN CAST( LEFT(X.TimeFrameLabel,4) as int)-2 AND CAST( LEFT(X.TimeFrameLabel,4) as int)	--last 3 fiscal years not including current
	AND RIGHT(X.TimeFrameLabel,2)=RIGHT(Y.TimeFrameLabel,2)	--same period
	AND X.Facility=Y.Facility	--same site
	AND X.Program=Y.Program		--same program
	GROUP BY X.TimeFrameLabel
	, X.Facility
	, X.Program
	;
	GO

	--add targets to the table
	UPDATE X
	SET X.[Target] = Y.[Target]
	FROM #TNR_ID05 as X INNER JOIN #TNR_ID05_targets as Y
	ON X.Facility=Y.Facility
	AND X.Program=Y.Program
	AND X.TimeFrameLAbel=Y.TimeFrameLabel
	WHERE Y.[Target] is not null
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

	-- probably want to remove non-VCH residents

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
	AND (ADTC.HealthAuthorityName = 'Vancouver Coastal' -- only include residents of Vancouver Coastal
		OR (ADTC.HealthAuthorityName = 'Unknown BC' AND (ADTC.IsHomeless = '1' OR ADTC.IsHomeless_PHC = '1'))
	) -- Include Unknown BC homeless population
	and ADTC.[AdjustedDischargeDate] is not null	--must have a discharge date
	and ADTC.DischargeAge > 1						-- only patients older than 1; replaces the new born criterion.
	and ADTC.[AccountType] in ('I','Inpatient','391')	--inpatient cases only
	and ADTC.[AdmissionAccountSubType]='Acute'		--inpatient subtype
	and LEFT(ADTC.DischargeNursingUnitCode,1)!='M'	--excludes ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')
	and ADTC.LOSDays>30		--only LLOS cases
		--AND ADTC.PatientServiceCode not in ('TC','EC')			--exclude transitional care and extended care census days
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
	, NULL as 'Target' --based on last 3 years of targets / 13 to be added
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Convenient Health Care' as 'IndicatorCategory'
	, '# Inpatient Days' as 'Units'
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
	, '# Inpatient Days' as 'Units'
	FROM #TNR_LLOS_06
	GROUP BY FiscalPeriodLong
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	,DischargeFacilityLongName
	;
	GO

	--append 0's for groups where no data was present but was expected
	INSERT INTO #TNR_ID06 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall,Scorecard_eligible, IndicatorCategory, Units)
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
	, '# Inpatient Days' as 'Units'
	FROM #placeholder as P
	LEFT JOIN #TNR_ID06 as I
	ON P.facility=I.Facility
	AND P.IndicatorId=I.IndicatorID
	AND P.Program=I.Program
	AND P.TimeFrame=I.TimeFrame
	WHERE P.IndicatorID= (SELECT distinct indicatorID FROM #TNR_ID06)
	AND I.[Value] is NULL
	;

	--set targets AVG of last 3 FY; TNSC 201904-08_TNS.Targets.xksx
	--BSC says the same thing but the definition iplies for the same YTD time range I think
	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID06_targets') IS NOT NULL DROP TABLE #TNR_ID06_targets;
	GO

	SELECT X.TimeFrameLabel
	, X.Facility
	, X.Program
	, AVG( Y.[Value] ) as 'Target'
	INTO #TNR_ID06_targets
	FROM #TNR_ID06 as X
	LEFT JOIN #TNR_ID06 as Y
	ON  CAST( LEFT(Y.TimeFrameLabel,4)  as int) -1 BETWEEN CAST( LEFT(X.TimeFrameLabel,4) as int)-2 AND CAST( LEFT(X.TimeFrameLabel,4) as int)	--last 3 fiscal years not including current
	AND RIGHT(X.TimeFrameLabel,2)=RIGHT(Y.TimeFrameLabel,2)	--same period
	AND X.Facility=Y.Facility	--same site
	AND X.Program=Y.Program	--same program
	GROUP BY X.TimeFrameLabel
	, X.Facility
	, X.Program

	--add targets to the table
	UPDATE X
	SET X.[Target] = Y.[Target]
	FROM #TNR_ID06 as X LEFT JOIN #TNR_ID06_targets as Y
	ON X.Facility=Y.Facility
	AND X.Program=Y.Program
	AND X.TimeFrameLAbel=Y.TimeFrameLabel
	WHERE Y.[Target] is not null
	;
	GO

-----------------------------------------------
-- ID07 ALC rate Excluding NewBorns and MHSU
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

	----------------------------------
	---- Finance Definition
	----------------------------------

		--compute and store indicators
		IF OBJECT_ID('tempdb.dbo.#TNR_inpatientDaysPGRM_ALCdenom') IS NOT NULL DROP TABLE #TNR_inpatientDaysPGRM_ALCdenom;
		GO

		SELECT X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, Y.ProgramDesc
		, SUM( CASE WHEN Y.ProgramDesc like '%Pop%' THEN BudgetedCensusDays
					WHEN X.GLAccountCode in ('S403105', 'S403145') THEN BudgetedCensusDays
					ELSE 0
				END
		) as 'BudgetedDays'
		, SUM( CASE WHEN Y.ProgramDesc like '%Pop%' THEN ActualCensusDays
					WHEN X.GLAccountCode in ('S403105', 'S403145') THEN ActualCensusDays
					ELSE 0
				END
		) as 'ActualDays'
		INTO #TNR_inpatientDaysPGRM_ALCdenom
		FROM #tnr_inpatientDaysByCC as X
		INNER JOIN FinanceMart.Finance.EntityProgramSubProgram as Y
		ON X.FinSiteID=Y.FinSiteID
		AND X.CostCenterCode =Y.CostCenterCode
		AND Y.ProgramDesc is not NULL
		--filters by account are done in the case statement ebcause we're not consistent on purpose
		GROUP BY X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, Y.ProgramDesc
		;
		GO

		--compute and store indicators
		IF OBJECT_ID('tempdb.dbo.#TNR_inpatientDaysPGRM_ALCnum') IS NOT NULL DROP TABLE #TNR_inpatientDaysPGRM_ALCnum;
		GO

		SELECT X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, Y.ProgramDesc
		, SUM( 1.0*BudgetedCensusDays) as 'BudgetedDays'
		, SUM( 1.0*ActualCensusDays	) as 'ActualDays'
		INTO #TNR_inpatientDaysPGRM_ALCnum
		FROM #tnr_inpatientDaysByCC as X
		INNER JOIN FinanceMart.Finance.EntityProgramSubProgram as Y
		ON X.FinSiteID=Y.FinSiteID
		AND X.CostCenterCode =Y.CostCenterCode
		AND Y.ProgramDesc is not NULL
		WHERE X.GLAccountCode in ('S403145') --filters done here because it makes more sense in the numerator case
		GROUP BY X.FiscalPeriodEndDate
		, X.FiscalPeriodStartDate
		, X.FiscalPeriodLong
		, X.EntityDesc
		, Y.ProgramDesc
		;
		GO

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID07') is not null DROP TABLE #TNR_ID07;
	GO

	--by program
	SELECT '07' as 'IndicatorID'
	, 'Richmond' as 'Facility'
	, D.ProgramDesc as 'Program'
	, D.FiscalPeriodEndDate as 'TimeFrame'
	, D.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'ALC Rate' as 'IndicatorName' 
	, ISNULL(N.ActualDays,0) as 'Numerator'
	, D.ActualDays as 'Denominator'
	, 1.0* ISNULL(N.ActualDays,0) / D.ActualDays as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P0' as 'Format'
	, 1.0*ISNULL(N.BudgetedDays,0)/IIF(D.BudgetedDays=0,1,D.BudgetedDays) as 'Target'	--finance target
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	, '% Rate' as 'Units'
	INTO #TNR_ID07
	FROM #TNR_inpatientDaysPGRM_ALCnum as N
	RIGHT JOIN #TNR_inpatientDaysPGRM_ALCdenom as D
	ON N.ProgramDesc =D.ProgramDesc
	AND N.FiscalPeriodLong = D.FiscalPeriodLong
	AND N.EntityDesc = D.EntityDesc
	WHERE D.EntityDesc='Richmond Health Services' --richmond only
	AND D.ActualDays >0
	--add overall
	UNION
	SELECT '07' as 'IndicatorID'
	, 'Richmond' as 'Facility'
	, 'Overall' as 'Program'
	, D.FiscalPeriodEndDate as 'TimeFrame'
	, D.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'ALC Rate' as 'IndicatorName' 
	, SUM(ISNULL(N.ActualDays,0)) as 'Numerator'
	, SUM(D.ActualDays) as 'Denominator'
	, 1.0* SUM( ISNULL(N.ActualDays,0) ) / SUM(D.ActualDays) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P0' as 'Format'
	, 1.0*SUM(ISNULL(N.BudgetedDays,0))/SUM( IIF(D.BudgetedDays=0,1,D.BudgetedDays) ) as 'Target'	--finance target
	, 'FinanceMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	, '% Rate' as 'Units'
	FROM #TNR_inpatientDaysPGRM_ALCnum as N
	RIGHT JOIN #TNR_inpatientDaysPGRM_ALCdenom as D
	ON N.ProgramDesc =D.ProgramDesc
	AND N.FiscalPeriodLong = D.FiscalPeriodLong
	AND N.EntityDesc = D.EntityDesc
	WHERE D.EntityDesc='Richmond Health Services' --richmond only
	AND D.ActualDays >0
	AND D.ProgramDesc != 'Mental Health'	--exclude MHSU from the total due to specs
	GROUP BY D.FiscalPeriodEndDate
	, D.FiscalPeriodLong
	;
	GO


	----------------------------------
	---- ADTC Definition
	----------------------------------
	---- links census data which has ALC information with admission/discharge information
	--IF OBJECT_ID('tempdb.dbo.#TNR_discharges_07') IS NOT NULL DROP TABLE #TNR_discharges_07;
	--GO

	--SELECT AccountNumber
	--, T.FiscalPeriodLong
	--, T.FiscalPeriodEndDate
	--, A.DischargeNursingUnitDesc
	--, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
	--, A.DischargeFacilityLongName
	--, A.[site]
	--INTO #TNR_discharges_07
	--FROM ADTCMart.[ADTC].[vwAdmissionDischargeFact] as A
	--INNER JOIN #TNR_FPReportTF as T						--identify the week
	--ON A.AdjustedDischargeDate BETWEEN T.FiscalPeriodStartDate AND T.FiscalPeriodEndDate
	--LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--identify the program
	--ON A.DischargeNursingUnitCode = MAP.nursingunitcode
	--AND A.AdjustedDischargeDate BETWEEN MAP.StartDate AND MAP.EndDate
	--WHERE A.[Site]='rmd'
	--AND A.[AdjustedDischargeDate] is not null		--discharged
	--AND A.[DischargePatientServiceCode]<>'NB'		--not a new born
	--AND A.[AccountType]='I'							--inpatient at richmond only
	--AND A.[AdmissionAccountSubType]='Acute'			--subtype acute; true inpatient
	--AND LEFT(A.DischargeNursingUnitCode,1)!='M'	--excludes ('Minoru Main Floor East','Minoru Main Floor West','Minoru Second Floor East','Minoru Second Floor West','Minoru Third Floor')
	--AND A.AdjustedDischargeDate > (SELECT MIN(FiscalPeriodStartDate) FROM #TNR_FPReportTF)	--discahrges in reporting timeframe
	--;
	--GO

	----links census data which has ALC information with admission/discharge information
	--IF OBJECT_ID('tempdb.dbo.#TNR_ALC_discharges_07') IS NOT NULL DROP TABLE #TNR_ALC_discharges_07;
	--GO

	----pull in ALC days per case
	--SELECT C.AccountNum
	--, SUM(CASE WHEN patientservicecode like 'AL[0-9]' or patientservicecode like 'A1[0-9]' THEN 1 ELSE 0 END) as 'ALC_Days'
	--, COUNT(*) as 'Census_Days'
	--INTO #TNR_ALC_discharges_07
	--FROM ADTCMart.adtc.vwCensusFact as C
	--WHERE exists (SELECT 1 FROM #TNR_discharges_07 as Y WHERE C.AccountNum=Y.AccountNumber AND C.[Site]=Y.[Site])
	--GROUP BY C.AccountNum
	--;
	--GO

	----compute and store metric
	--IF OBJECT_ID('tempdb.dbo.#TNR_ID07') IS NOT NULL DROP TABLE #TNR_ID07;
	--GO

	--SELECT 	'07' as 'IndicatorID'
	--, X.DischargeFacilityLongName as 'Facility'
	--, X.Program as 'Program'
	--, FiscalPeriodEndDate as 'TimeFrame'
	--, FiscalPeriodLong as 'TimeFrameLabel'
	--, 'Fiscal Period' as 'TimeFrameType'
	--, 'ALC Rate Based on Discharges' as 'IndicatorName'
	--, SUM(Y.ALC_Days) as 'Numerator'
	--, SUM(Y.Census_Days) as 'Denominator'
	--, 1.0*SUM(Y.ALC_Days)/SUM(Y.Census_Days) as 'Value'
	--, 'Below' as 'DesiredDirection'
	--, 'P0' as 'Format'
	----, CASE WHEN X.FiscalPeriodEndDate between '4/1/2013' and '3/31/2014' THEN 0.099
	----	   WHEN X.FiscalPeriodEndDate between '4/1/2014' and '3/31/2015' THEN 0.11
	----	   WHEN X.FiscalPeriodEndDate between '4/1/2015' and '3/31/2016' THEN 0.115
	----	   ELSE 0.115 
	----END 
	--, CAST(NULL as float) as 'Target'
	--, 'ADTCMart' as 'DataSource'
	--, 0 as 'IsOverall'
	--, 1 as 'Scorecard_eligible'
	--, 'Exceptional Care' as 'IndicatorCategory'
	--, '% Rate' as 'Units'
	--INTO #TNR_ID07
	--FROM #TNR_discharges_07 as X
	--LEFT JOIN #TNR_ALC_discharges_07 as Y
	--ON X.AccountNumber=Y.AccountNum
	--GROUP BY X.FiscalPeriodLong
	--, X.FiscalPeriodEndDate
	--, X.Program
	--, X.DischargeFacilityLongName
	----add overall
	--UNION 
	--SELECT '07' as 'IndicatorID'
	--, X.DischargeFacilityLongName as 'Facility'
	--, 'Overall' as 'Program'
	--, FiscalPeriodEndDate as 'TimeFrame'
	--, FiscalPeriodLong as 'TimeFrameLabel'
	--, 'Fiscal Period' as 'TimeFrameType'
	--, 'ALC Rate Based on Discharges' as 'IndicatorName'
	--, SUM(Y.ALC_Days) as 'Numerator'
	--, SUM(Y.Census_Days) as 'Denominator'
	--, 1.0*SUM(Y.ALC_Days)/SUM(Y.Census_Days) as 'Value'
	--, 'Below' as 'DesiredDirection'
	--, 'P0' as 'Format'
	----, CASE WHEN X.FiscalPeriodEndDate between '4/1/2013' and '3/31/2014' THEN 0.099
	----	   WHEN X.FiscalPeriodEndDate between '4/1/2014' and '3/31/2015' THEN 0.11
	----	   WHEN X.FiscalPeriodEndDate between '4/1/2015' and '3/31/2016' THEN 0.115
	----	   ELSE 0.115 
	----END 
	--, CAST(NULL as float) as 'Target'
	--, 'ADTCMart' as 'DataSource'
	--, 1 as 'IsOverall'
	--, 1 as 'Scorecard_eligible'
	--, 'Exceptional Care' as 'IndicatorCategory'
	--, '% Rate' as 'Units'
	--FROM #TNR_discharges_07 as X
	--LEFT JOIN #TNR_ALC_discharges_07 as Y
	--ON X.AccountNumber=Y.AccountNum
	--GROUP BY X.FiscalPeriodLong
	--, X.FiscalPeriodEndDate
	--, X.DischargeFacilityLongName
	--;
	--GO

	--------------------------------------

	----ALC targets for richmond overall from BSI to match BSC, will apply to all programs
	--IF OBJECT_ID('tempdb.dbo.#TNR_ID07_targets') IS NOT NULL DROP TABLE #TNR_ID07_targets;
	--GO

	--SELECT LEFT(FullFiscalYear,2)+RIGHT(FullFiscalYear,2) as 'FiscalYear'
	--, CASE WHEN EntityIndicatorID = 35 THEN 'Richmond Hospital'
	--	   WHEN EntityIndicatorID = 34 THEN 'Vancouver General Hospital'
	--	   WHEN EntityIndicatorID = 33 THEN 'Overall'
	--	   ELSE 'Unmapped'
	--END as 'Facility'
	--, [FY_YTD]/100 as 'Target'
	--INTO #TNR_ID07_targets
	--FROM BSI.[BSI].[IndicatorSummaryFact] 
	--WHERE indicatorID=5		--ALC indicator on BSC as of 20190801
	--and EntityIndicatorID=35 --richmond overall
	--and FactDataRowTypeID=2 --target data
	--AND [FY_YTD]  is not null
	--;
	--GO

	---- update targets
	--UPDATE X
	--SET [Target] = Y.[Target]
	--FROM #TNR_ID07 as X
	--INNER JOIN #TNR_ID07_targets as Y
	--ON X.Facility=Y.Facility	--same facility
	--AND LEFT(X.TimeFrameLabel,4) = Y.FiscalYear --same fiscal year
	----AND X.Program=Y.Program	; no program in BSI apply blanket rate target to all services
	--;
	--GO

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
	, '# Readmissions' as 'Units'
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
	, '# Readmissions' as 'Units'
	FROM #tnr_28dreadd2
	GROUP BY CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	, FiscalPeriodLong
	, IndicatorName
	;
	GO

	--compute traget using last year as a baseline average
	IF OBJECT_ID('tempdb.dbo.#TNR_ID09_targets') is not null DROP TABLE #TNR_ID09_targets;
	GO

	SELECT LEFT(TimeFrameLabel,4) as 'FiscalYear'
	, Facility
	, Program
	, AVG(Value) as 'Target'
	INTO #TNR_ID09_targets
	FROM #TNR_ID09
	GROUP BY LEFT(TimeFrameLabel,4)
	, Facility
	, Program
	;
	GO

	-- update targets
	UPDATE X
	SET X.[Target] = Y.[Target]
	FROM #TNR_ID09 as X
	INNER JOIN #TNR_ID09_targets as Y
	ON X.Facility=Y.Facility	--same facility
	AND X.Program=Y.Program		--same program
	AND CAST(LEFT(X.TimeFrameLabel,4) as int) = CAST(Y.FiscalYear as int) +1 --last fiscal year
	WHERE Y.[Target] is not null
	;
	GO

-----------------------------------------------
-- ID10 Number of Beds Occupied (excl. Mental Health, ED, DTU, PAR, Periops)   --- currently Average Census
-----------------------------------------------
	/*Comments: We are only including accounts S403105, S403107, and S403145 in this indicator similar to the BSC per March 25, 2020.
	The BSC excludes newborn days, and for some reason inpatient NICU and SCN days.
	The claim is that the MoH asked that we exclude NICUs and Carolina sent over some DMR internal documentation stating that they exclude it.
	However, despite my best efforts I haven't been able to very this is a MoH source.
	Peter notes that the MoH excludes newborns, but it was always up to our internal interpretation how we achieve this.

	This indicator includes ALC days.
	Pop and family health includes the NICU days under S403430 for practical purposes, but the overall does not.
	*/
	
	-----------------------------
	-- for the overall which has a tweak it excludes some days in Pop&family health under GL account S403430
	-----------------------------
	

	--compute and store indicators
	IF OBJECT_ID('tempdb.dbo.#TNR_ID10') IS NOT NULL DROP TABLE #TNR_ID10;
	GO
	
	SELECT '10' as 'IndicatorID'
	, CASE WHEN EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE NULL
	END as 'Facility'
	, [ProgramDesc] as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Inpatient census per day in the period' as 'IndicatorName'
	, SUM(ActualCensusDays) as 'Numerator'
	, (1+DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate)) as 'Denominator'
	, 1.0*SUM(ActualCensusDays)/(1+DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate))  as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, 1.0*SUM(BudgetedCensusDays)/(1+DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate))  as 'Target'		--based on budget
	, 'FinanceMart' as 'DataSource'	--Lamberts groupings
	, CASE WHEN ProgramDesc='Overall' THEN 1 ELSE 0 END as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	, 'Avg. Inpatient Days' as 'Units'
	INTO #TNR_ID10
	FROM #TNR_inpatientDaysPGRM
	WHERE (
	Entitydesc ='Richmond Health Services' 
	AND ProgramDesc not in ('Long Term Care Services')
	)	--we don't want to keep these indicators for RHS
	GROUP BY EntityDesc
	, ProgramDesc
	, FiscalPeriodLong
	, FiscalPeriodStartDate
	, FiscalPeriodEndDate
	;
	GO

	--only unallocated can have 0 days legitimately
	DELETE FROM #TNR_ID10 WHERE program not like  '%Unallocated%' AND Numerator=0	--records are too early
	;
	GO

-----------------------------------------------
-- ID11 Beds occupied as a % of budgeted bed capacity (excl. Mental Health, ED ,DTU, PAR, Periop) 
-----------------------------------------------

	--a finance mart based definition; doesn't agree with the historical vancouver extract likely because of labels.
	IF OBJECT_ID('tempdb.dbo.#TNR_ID11') IS NOT NULL DROP TABLE #TNR_ID11;
	GO

	SELECT '11' as 'IndicatorID'
	, CASE WHEN EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE NULL
	END as 'Facility'
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
	, 1.00 as 'Target'
	, 'FinanceMart' as 'DataSource'	--Lamberts groupings
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	, '% of beds occupied' as 'Units'
	INTO #TNR_ID11
	FROM #TNR_inpatientDaysPGRM
	WHERE EntityDesc='Richmond Health Services'		--only want the richmond IP days.
	;
	GO

	--only unallocated can have 0 beds occupied legitimately
	DELETE FROM #TNR_ID11 
	WHERE program not like  '%Unallocated%'
	 AND (Denominator=0 or Numerator=0)	--records are too early	; have an issue with numerator =0 that is also wrong, but it's not addressed
	;
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
	, CASE WHEN EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE EntityDesc
	END as 'Facility'
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
	, IIF(OT.Bud_ProdHrs =0, 0, 1.0 * Bud_OTHrs/OT.Bud_ProdHrs) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	, '% OT Rate' as 'Units'
	INTO #TNR_ID12
	FROM #tnr_otHours as OT
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON OT.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND OT.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	--add overall
	UNION
	SELECT '12' as 'IndicatorID'
	, CASE WHEN EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE EntityDesc
	END as 'Facility'
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
	, IIF(SUM(OT.Bud_ProdHrs) =0, 0, 1.0 * SUM(Bud_OTHrs)/SUM(OT.Bud_ProdHrs)  ) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	, '% OT Rate' as 'Units'
	FROM #tnr_otHours as OT
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON OT.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND OT.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	WHERE OT.ProgramDesc not in ('Health Protection','BISS','Regional Clinical Services','Volunteers','Comm Geriatrics & Spiritual Cr')	--remove from to match Riley's included programs. These are regional not richmond specific.
	GROUP BY EntityDesc
	, D.FiscalPeriodEndDate
	, D.FiscalPeriodLong
	;
	GO

	--only unallocated can have 0 beds occupied legitimately
	DELETE FROM #TNR_ID12 WHERE program not like  '%Unallocated%' AND Numerator=0	--records are too early
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
	, CASE WHEN EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE EntityDesc
	END as 'Facility'
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
	, IIF( ST.Bud_ProdHrs =0, 0, 1.0 * ST.Bud_STHrs/ST.Bud_ProdHrs  ) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	, '% ST Rate' as 'Units'
	INTO #TNR_ID13
	FROM #tnr_sickHours as ST
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON ST.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND ST.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	--add overall
	UNION
	SELECT '13' as 'IndicatorID'
	, CASE WHEN EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE EntityDesc
	END as 'Facility'
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
	, IIF(SUM(ST.Bud_ProdHrs) =0, 0, 1.0 * SUM(ST.Bud_STHrs)/SUM(ST.Bud_ProdHrs)  ) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	, '% ST Rate' as 'Units'
	FROM #tnr_sickHours as ST
	INNER JOIN #TNR_FPReportTF as D			--get the fiscal period descriptors
	ON ST.FiscalYearLong=D.FiscalYearLong	--same fiscal year
	AND ST.FiscalPeriod=D.FiscalPeriod		--same fiscal period
	WHERE ST.ProgramDesc not in ('Health Protection','BISS','Regional Clinical Services','Volunteers','Comm Geriatrics & Spiritual Cr')	--remove from to match Riley's included programs. These are regional not richmond specific.
	GROUP BY EntityDesc
	, D.FiscalPeriodEndDate
	, D.FiscalPeriodLong
	;
	GO

	--only unallocated can have 0 beds occupied legitimately
	DELETE FROM #TNR_ID13 WHERE program not like  '%Unallocated%' AND Numerator=0	--records are too early
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
	, 'Thousands of $' as 'Units'
	INTO #TNR_ID14
	FROM #TNR_revExpenses as ND
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
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Great Place to Work' as 'IndicatorCategory'
	, 'Thousands of $' as 'Units'
	FROM #TNR_revExpenses as ND
	-- includes all programs
	GROUP BY FiscalPeriodEndDate
	, FiscalPeriodLong
	;
	GO

	--identifies records that are pulled in too early. It is not realistic to have 0 revenue and expenses except for special programs.
	DELETE FROM #TNR_ID14 WHERE Numerator =0 AND Denominator=0 AND program not like '%Unallocated%';
	GO
		
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
	, CASE WHEN h.EntityDesc ='Richmond Health Services' THEN 'Richmond Hospital'
			ELSE NULL
	END as 'Facility'
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
	, 'Hours per IP Day' as 'Units'
	INTO #TNR_ID15
	FROM  #tnr_productiveHoursPRGM as h
	INNER JOIN #TNR_inpatientDaysPGRM as ip
	ON h.FiscalPeriodLong=ip.FiscalPeriodLong
	AND h.ProgramDesc=ip.ProgramDesc
	AND h.EntityDesc=ip.EntityDesc
	WHERE (
	h.Entitydesc ='Richmond Health Services' 
	AND h.ProgramDesc not in ('Long Term Care Services')
	)	--we don't want to keep these indicators for RHS
	GROUP BY h.EntityDesc
	, h.ProgramDesc
	, h.FiscalPeriodEndDate
	, h.FiscalPeriodLong
	;
	GO

	--identifies records that are pulled in too early. It is not realistic to have 0 revenue and expenses except for special programs.
	DELETE FROM #TNR_ID15 WHERE Denominator=0 AND program not like '%Unallocated%';
	GO

-----------------------------------------------
-- ID16 Percent of surgical Cases Treated Within Target Wait Time
-----------------------------------------------
	/*	Purpose: to compute the percentage of surgeries completed within the target wait time. Wailist for surgery to surgery performed.
		Author: Kaloupis Peter
		Co-author: Hans Aisake
		Date Created: 2016
		Date Modified: April 1, 2019
		Inclusions/Exclusions: 
		Comments:
			May need to add 0 logics. 0 Ortho surgeries recorded in 2020/21-P01.

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
	, '% Surgical Cases Treated Within Target Wait Time' as 'IndicatorName'
	, COUNT( CASE WHEN O.ismeetingtarget =1 THEN 1 ELSE NULL END) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*COUNT( CASE WHEN O.ismeetingtarget =1 THEN 1 ELSE NULL END)/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P1' as 'Format'
	, 0.85 as 'Target'
	, 'ORMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	, '% cases' as 'Units'
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
	, '% Surgical Cases Treated Within Target Wait Time' as 'IndicatorName'
	, COUNT( CASE WHEN O.ismeetingtarget =1 THEN 1 ELSE NULL END) as 'Numerator'
	, count(*) as 'Denominator'
	, 1.0*COUNT( CASE WHEN O.ismeetingtarget =1 THEN 1 ELSE NULL END)/count(*)  as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'P1' as 'Format'
	, 0.85 as 'Target'
	, 'ORMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	, '% cases' as 'Units'
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

	--create all periods and specialities so we can create 0 volumes when required
	IF OBJECT_ID('tempdb.dbo.#placeholder_16') IS NOT NULL DROP TABLE #placeholder_16;
	GO

	SELECT * 
	INTO #placeholder_16
	FROM 
	--pull time frame attrbiutes assuming each is populated by something
	(SELECT distinct TimeFrameLabel, TimeFrameType, TimeFrame FROM #TNR_ID16) as X
	CROSS JOIN 
	(	--pull attributse from the indicator table
		SELECT distinct IndicatorID, Facility, LoggedMainsurgeonSpecialty, IndicatorName, DesiredDirection, [Format]
		, 0.85 as 'Target'	--should be a copy of the logic in the indicator computation above
		, DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
		FROM #TNR_ID16	) as Y
	;
	GO

	--insert 0 rows where appliable
	INSERT INTO #TNR_ID16 (IndicatorID, Facility, LoggedMainsurgeonSpecialty, TimeFrame, TimeFrameLabel, TimeFrameType, IndicatorName, Numerator, Denominator, [Value], DesiredDirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units)
	SELECT X.IndicatorID
	, X.Facility, X.LoggedMainsurgeonSpecialty, X.TimeFrame, X.TimeFrameLabel, X.TimeFrameType, X.IndicatorName
	, ISNULL(Y.[Numerator],0) as 'Numerator'
	, ISNULL(Y.[Denominator],0) as 'Denominator'
	, ISNULL(Y.[Value],0) as 'Value'	--this is undefined technically as 0/0 but in this case we want to show a 0% rate because no surgeries are being performed, rather than 100% and we can settle the definition
	, X.DesiredDirection, X.[Format], X.[Target], X.DataSource, X.IsOverall, X.Scorecard_eligible, X.IndicatorCategory, X.Units
	FROM #placeholder_16 as X
	LEFT JOIN #TNR_ID16 as Y
	ON X.IndicatorID=Y.IndicatorID
	AND X.Facility=Y.Facility
	AND X.LoggedMainsurgeonSpecialty=Y.LoggedMainsurgeonSpecialty
	AND X.TimeFrame=Y.TimeFrame
	WHERE Y.[Value] is null
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
	, '# ED visits' as 'Units'
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
	INSERT INTO #TNR_ID17 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall, Scorecard_eligible, IndicatorCategory, Units)
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
	, '# ED visits' as 'Units'
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
--ID18 Short Stay discahrges (<=48hrs) excludes Newborns
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
	, '# discharges' as 'Units'
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
	, '# discharges' as 'Units'
	FROM #TNR_SSad_18
	GROUP BY FiscalPeriodLong
	, fiscalPeriodEndDate
	, DischargeFacilityLongName
	;
	GO

-----------------------------------------------
--ID 19 ED visits
-----------------------------------------------
	/*
	Purpose: To compute how many people visit ED
	Author: Hans Aisake
	Date Created: August 15, 2019
	Date Updated: 
	Inclusions/Exclusions:
	Comments:
		Unkown program is when patients are admitted but they never arrive at an inpatient unit and become DDFEs.
		It is included in the overall, but cannot be allocated to any program.

	*/

	--preprocess ED data and identify reporting time frames
	IF OBJECT_ID('tempdb.dbo.#tnr_ed19') IS NOT NULL DROP TABLE #tnr_ed19;
	GO

	--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
	SELECT 	T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, T.days_in_fp
	, X.VisitID
	, X.Program
	, X.FacilityLongName
	INTO #TNR_ed19
	FROM
	(
		SELECT ED.StartDate
		, ED.VisitID
		, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
		, ED.FacilityLongName
		FROM EDMart.dbo.vwEDVisitIdentifiedRegional as ED
		LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--link to a fact table that identifies which program each unit goes to; not maintained by DMR
		ON ED.InpatientNursingUnitID= MAP.NursingUnitID			--same nursing unit id
		AND ED.StartDate BETWEEN MAP.StartDate AND MAP.EndDate	--within mapping dates; you could argue for inpatient date, but it's a minor issue
		WHERE ED.FacilityShortName='RHS'
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
	IF OBJECT_ID('tempdb.dbo.#TNR_ID19') IS NOT NULL DROP TABLE #TNR_ID19;
	GO

	SELECT 	'19' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Number of Emergency Visits (period adjusted)' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, 1.0*count(distinct VisitID)*28/AVG(days_in_fp) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# ED visits' as 'Units'
	INTO #TNR_ID19
	FROM #TNR_ed19
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, Program
	, FacilityLongName
	--add overall indicator
	UNION
	SELECT 	'19' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Number of Emergency Visits (period adjusted)' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, 1.0*count(distinct VisitID)*28/AVG(days_in_fp) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# ED visits' as 'Units'
	FROM #TNR_ed19
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

-----------------------------------------------
--ID 20 ED Admission Rate
-----------------------------------------------
	/*
	Purpose: To compute the ED admission Rate
	Author: Hans Aisake
	Date Created: August 15, 2019
	Date Updated: 
	Inclusions/Exclusions:
	Comments:
		Unkown program is when patients are admitted but they never arrive at an inpatient unit and become DDFEs.
		It is included in the overall, but cannot be allocated to any program.

	*/

	--preprocess ED data and identify reporting time frames
	IF OBJECT_ID('tempdb.dbo.#tnr_ed20') IS NOT NULL DROP TABLE #tnr_ed20;
	GO

	--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
	SELECT 	T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, X.VisitID
	, X.AdmittedFlag
	, X.Program
	, X.FacilityLongName
	INTO #TNR_ed20
	FROM
	(
		SELECT ED.StartDate
		, ED.VisitID
		, ED.AdmittedFlag
		, ISNULL(MAP.NewProgram,'Unknown') as 'Program'
		, ED.FacilityLongName
		FROM EDMart.dbo.vwEDVisitIdentifiedRegional as ED
		LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_NU_PROGRAM_MAP_ADTC] as MAP	--link to a fact table that identifies which program each unit goes to; not maintained by DMR
		ON ED.InpatientNursingUnitID= MAP.NursingUnitID			--same nursing unit id
		AND ED.StartDate BETWEEN MAP.StartDate AND MAP.EndDate	--within mapping dates; you could argue for inpatient date, but it's a minor issue
		WHERE ED.FacilityShortName='RHS'
		--AND ED.admittedflag=1 --need both admits and non admits
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
	IF OBJECT_ID('tempdb.dbo.#TNR_ID20') IS NOT NULL DROP TABLE #TNR_ID20;
	GO

	SELECT 	'20' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Emergency Admission Rate' as 'IndicatorName'
	, count(distinct CASE WHEN AdmittedFlag=1 THEN VisitID ELSE NULL END) as 'Numerator'
	, count(distinct VisitID) as 'Denominator'
	, 1.0*count(distinct CASE WHEN AdmittedFlag=1 THEN VisitID ELSE NULL END)/count(distinct VisitID) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P2' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'Admission Rate' as 'Units'
	INTO #TNR_ID20
	FROM #TNR_ed20
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,Program
	, FacilityLongName
	--add overall indicator
	UNION
	SELECT 	'20' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Emergency Admission Rate' as 'IndicatorName'
	, count(distinct CASE WHEN AdmittedFlag=1 THEN VisitID ELSE NULL END) as 'Numerator'
	, count(distinct VisitID) as 'Denominator'
	, 1.0*count(distinct CASE WHEN AdmittedFlag=1 THEN VisitID ELSE NULL END)/count(distinct VisitID) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P2' as 'Format'
	, NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'Admission Rate' as 'Units'
	FROM #TNR_ed20
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

-----------------------------------------------
--ID 21 ED Admission Volume
-----------------------------------------------
	/*
	Purpose: To compute the ED admission volumes
	Author: Hans Aisake
	Date Created: August 15, 2019
	Date Updated: 
	Inclusions/Exclusions:
	Comments:
		Unkown program is when patients are admitted but they never arrive at an inpatient unit and become DDFEs.
		It is included in the overall, but cannot be allocated to any program.

	*/

	--preprocess ED data and identify reporting time frames
	IF OBJECT_ID('tempdb.dbo.#tnr_ed21') IS NOT NULL DROP TABLE #tnr_ed21;
	GO

	--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
	SELECT 	T.FiscalPeriodLong
	, T.FiscalPeriodEndDate
	, X.VisitID
	, X.AdmittedFlag
	, X.Program
	, X.FacilityLongName
	INTO #TNR_ed21
	FROM
	(
		SELECT ED.StartDate
		, ED.VisitID
		, ED.AdmittedFlag
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
	IF OBJECT_ID('tempdb.dbo.#TNR_ID21') IS NOT NULL DROP TABLE #TNR_ID21;
	GO

	SELECT 	'21' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Emergency Admissions' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, count(distinct CASE WHEN AdmittedFlag=1 THEN VisitID ELSE NULL END) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# admissions' as 'Units'
	INTO #TNR_ID21
	FROM #TNR_ed21
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,Program
	, FacilityLongName
	--add overall indicator
	UNION
	SELECT 	'21' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Emergency Admissions' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, count(distinct CASE WHEN AdmittedFlag=1 THEN VisitID ELSE NULL END) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	,  NULL as 'Target'
	, 'EDMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# admissions' as 'Units'
	FROM #TNR_ed21
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

-----------------------------------------------
-- ID22 ALC Days
-----------------------------------------------
	/*
	Purpose: To compute how many census inpatient days in the period were ALC 
	Author: Hans Aisake
	Date Created: June 14, 2018
	Date Updated: Feb 25, 2021
	Inclusions/Exclusions:
		- see indicator 07 for details.

	Comments:
		- changed to a finance mart definition from and ADTC census definition on Feb 25, 2021. This keeps ALC consistent throughout this product.
	*/

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID22') IS NOT NULL DROP TABLE #TNR_ID22;
	GO

	SELECT 	'22' as 'IndicatorID'
	, 'Richmond' as 'Facility'
	, ProgramDesc as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'ALC Days in the period' as 'IndicatorName'
	, CAST(NULL as int) as 'Numerator'
	, CAST(NULL as int) as 'Denominator'
	, ActualDays as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, BudgetedDays as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# ALC Days' as 'Units'
	INTO #TNR_ID22
	FROM #TNR_inpatientDaysPGRM_ALCnum
	WHERE EntityDesc='Richmond Health Services'
	--add overall
	UNION 
	SELECT '22' as 'IndicatorID'
	, 'Richmond' as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'ALC Days in the period' as 'IndicatorName'
	, CAST(NULL as int) as 'Numerator'
	, CAST(NULL as int) as 'Denominator'
	, SUM(ActualDays) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, SUM(BudgetedDays) as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# ALC Days' as 'Units'
	FROM #TNR_inpatientDaysPGRM_ALCnum
	WHERE EntityDesc='Richmond Health SErvices'
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	;
	GO

-----------------------------------------------
-- IDHHDASH pull indicators from the HH Dashboard
-----------------------------------------------
	/*
	Purpose: To pull the indicators from the HH Dashboard
	Author: Hans Aisake
	Date Created: June 14, 2018
	Date Updated: August 15, 2019
	Inclusions/Exclusions:
	Comments:

		% RC Placements from Community
		% of Face to Face Nursing Visits that were Ambulatory
		% of HH Clients with an ED Visit
		7 Day ED Revisit Rate for HH Clients
		% HH Clients with an Acute Admission
		% of overall hospital deaths for clients known to VCH community programs
		Average hospital days in the last 6 months of life for clients known to VCH community programs
		% Hospice Placements from Community

	*/

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_IDHHDASH') IS NOT NULL DROP TABLE #TNR_IDHHDASH;
	GO

	SELECT 
	CAST (CASE	WHEN IndicatorID =1 THEN 23
				WHEN IndicatorID =2 THEN 24
				WHEN IndicatorID =9 THEN 25
				WHEN IndicatorID =11 THEN 26
				WHEN IndicatorID =12 THEN 27
				WHEN IndicatorID =15 THEN 28
				WHEN IndicatorID =16 THEN 29
				WHEN IndicatorID =22 THEN 30
				ELSE 0
		END
	as varchar(2)) as 'IndicatorID'
	, CASE WHEN [Location] ='Richmond' THEN 'Richmond Hospital'
		   ELSE [Location]
	END as 'Facility'
	, (SELECT distinct TOP 1  program FROM #TNR_ID01 WHERE program like '%home%')  as 'Program'	--might want to switch to home and community care program
	, TimeFrameEndDate as 'TimeFrame'
	, CASE  WHEN TimeFrameType='P' THEN TimeFrame
			WHEN TimeFrameType='Q' THEN RIGHT( TimeFrame,LEN( TimeFrame)-5)
			ELSE ''
	END as 'TimeFrameLabel'
	, CASE	WHEN TimeFrameType='P' THEN 'Fiscal Period'
			WHEN TimeFrameType='Q' THEN 'FQ HH'
			ELSE 'Fiscal Year'
	END as 'TimeFrameType'
	, REPLACE(IndicatorName,'%','Percent') as 'IndicatorName'
	, Numerator
	, Denominator
	, [Metric] as 'Value'
	, DesiredDirection
	, [Format]
	, [Target]
	, DataSource
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, CAST(NULL as varchar(255)) as 'Units'	--needs to be filled in with a case statement
	INTO #TNR_IDHHDASH
	FROM DSSI.dbo.HHDASH_MasterTableAll_2 
	WHERE indicatorId in (1,2,9,11,12,15,16,22)	--see comments
	and locationtype='CommunityRegion'		--main criteria
	and [Location]='Richmond'				--probably remove for a regional version
	;
	GO

-----------------------------------------------
-- ID31 Average Length of Stay of Long Length of Stay (>30 days) Patients Snapshot
-----------------------------------------------
	/*
	Purpose: To compute the average length of stay of LLOS patients in the snapshot.
	Author: Hans Aisake
	Date Created: August 20, 2019
	Date Updated: 
	Inclusions/Exclusions:
		- true inpatient records only
		- excludes newborns
	Comments:
		I took the base query for indicator 471 for the BSC version FROM Emily, but modified it to be richmond specific.
		Targets are absed on the BSI fiscal period targets. If it is a snapshot it shouldn't be directly comprable to the thursday week end.
		It doens't match the BSc front page because they average accross several periods where as here we just show what it was for the period.
	
	*/
	
	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID31') IS NOT NULL DROP TABLE #TNR_ID31;
	GO

	SELECT '31' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, Program as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Average Length of Stay of Long Length of Stay (>30 days) Patients Snapshot (excl. MH)' as 'IndicatorName' 
	, SUM(LLOSDays) as 'Numerator'
	, COUNT(1) as 'Denominator'
	, AVG(1.0*LLOSDays) as 'Value'
	 , 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'avg. LLOS days' as 'Units'
	INTO #TNR_ID31
	FROM #TNR_LLOS_data
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	,Program
	, FacilityLongName
	--add overall
	UNION
	SELECT '31' as 'IndicatorID'
	, FacilityLongName as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Average Length of Stay of Long Length of Stay (>30 days) Patients Snapshot (excl. MH)' as 'IndicatorName'  
	, SUM(LLOSDays) as 'Numerator'
	, COUNT(1) as 'Denominator'
	, AVG(1.0*LLOSDays) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'ADTCMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'avg. LLOS days' as 'Units'
	FROM #TNR_LLOS_data
	WHERE Program not like '%Mental%'
	GROUP BY FiscalPeriodLong
	, FiscalPeriodEndDate
	, FacilityLongName
	;
	GO

	----remove population and family health because it's not right for this indicator
	--DELETE FROM #TNR_ID23 WHERE Program ='Pop & Family Hlth & Primary Cr'
	--GO

	--append 0's ; might be something wrong here
	INSERT INTO #TNR_ID31 (IndicatorID, Facility,IndicatorName, Program,TimeFrame, TimeFrameLabel, TimeFrameType,Numerator,Denominator,[Value],DesiredDirection,[Format],[Target],DataSource,IsOverall,Scorecard_eligible, IndicatorCategory, Units)
	SELECT 	'31' as 'IndicatorID'
	, p.facility
	, p.IndicatorName
	, P.Program
	, P.TimeFrame
	, P.TimeFrameLabel as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, NULL as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'ADTCMart' as 'DataSource'
	, CASE WHEN P.Program ='Overall' THEN 1 ELSE 0 END as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'avg. LLOS days' as 'Units'
	FROM #placeholder as P
	LEFT JOIN #TNR_ID31 as I
	ON P.facility=I.Facility
	AND P.IndicatorId=I.IndicatorID
	AND P.Program=I.Program
	AND P.TimeFrame=I.TimeFrame
	WHERE P.IndicatorID= (SELECT distinct indicatorID FROM #TNR_ID31)
	AND I.[Value] is NULL
	;
	GO

-----------------------------------------------
-- ID32 ID33  7 day and 28 day readmission rates excluding MH from overall
-----------------------------------------------
	--we could combine this with an earlier indicator

	--pulled from iCareMart and convert the wkend to a date; for efficiency of joins
	IF OBJECT_ID('tempdb.dbo.#tnr_readmits') is not null DROP TABLE #tnr_readmits;
	GO

	SELECT [Facility]
	, [GroupName]
	, [Indicator]
	, [Value]
	, CONVERT(datetime, CONVERT(varchar(8),WkEnd),112) as 'ThursdayWkEnd'
	INTO #tnr_readmits
	FROM [ICareMart].[dbo].[icareFinalComputationsUnpivot]
	WHERE indicator in ('Readmission28D', 'Readmission7D', 'Discharge')	--have to pull volumes so we can dervive FP rates; the table only has weekly rates
	AND facility='RHS'
	;
	GO

	--put readmits and discharges side by side
	IF OBJECT_ID('tempdb.dbo.#tnr_readmits2') is not null DROP TABLE #tnr_readmits2;
	GO

	SELECT X.Facility
	, X.GroupName
	, X.Indicator
	, X.ThursdayWkEnd
	, X.[Value] as 'NumReadmits'
	, Y.[Value] as 'Discharges'
	INTO #tnr_readmits2
	FROM #tnr_readmits as X
	LEFT JOIN #tnr_readmits as Y
	ON X.Facility=Y.Facility		--same facility
	AND X.GroupName=Y.GroupName		--same group
	AND Y.Indicator='Discharge'		--join on discharges
	AND X.ThursdayWkEnd= Y.ThursdayWkEnd	--same week
	WHERE X.indicator in ('Readmission28D', 'Readmission7D')	--only keep readmits from X
	;
	GO

	--assigned fiscal periods and aggregate the data
	IF OBJECT_ID('tempdb.dbo.#tnr_readmits3') is not null DROP TABLE #tnr_readmits3;
	GO

	SELECT D.FiscalPeriodLong
	, facility
	, D.FiscalPeriodStartDate
	, D.FiscalPeriodEndDate
	, CASE  WHEN indicator = 'Readmission7D' THEN 'All Cause Readmission Rate within 7-days (excl MH and STAT)'
			WHEN indicator = 'Readmission28D' THEN 'All Cause Readmission Rate within 28-days (excl MH and STAT)'
			ELSE NULL
	END as 'IndicatorName'
	, CASE  WHEN indicator = 'Readmission7D' THEN '32'
			WHEN indicator = 'Readmission28D' THEN '33'
			ELSE NULL
	END as 'IndicatorID'
	, MAP.NewProgram as 'Program'
	, SUM([NumReadmits]) as 'Numerator'
	, SUM([Discharges]) as 'Denominator'
	, 1.0*SUM([NumReadmits]) / SUM([Discharges]) as 'Value'
	INTO #tnr_readmits3
	FROM #tnr_readmits2 as X
	INNER JOIN #TNR_FPReportTF as D		--to get fiscal periods we want to report on
	ON X.ThursdayWkEnd BETWEEN D.FiscalPeriodStartDate AND D.FiscalPeriodEndDate	--thursday week is a part of the period
	INNER JOIN DSSI.dbo.RH_VisibilityWall_NU_PROGRAM_MAP_ADTC as MAP	--to map nursing units to programs
	ON GroupName=Map.nursingunitcode		--same nursing unit
	AND X.ThursdayWkEnd BETWEEN MAP.StartDate AND MAP.EndDate	--active mapping date for the nursing unt; from time to time they "Change" or are "moved"
	GROUP BY D.FiscalPeriodLong
	, D.FiscalPeriodStartDate
	, D.FiscalPeriodEndDate
	, Facility
	, indicator
	, Map.NewProgram 
	;

	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID32_ID33') IS NOT NULL DROP TABLE #TNR_ID32_ID33;
	GO

	SELECT IndicatorID
	, CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END as 'Facility'
	, Program
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, IndicatorName
	, Numerator
	, Denominator
	, [Value]
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'iCareMart adjusted' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'readmissions rate' as 'Units'
	INTO #TNR_ID32_ID33
	FROM #tnr_readmits3
	--add overall
	UNION
	SELECT IndicatorID
	, CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END as 'Facility'
	, 'Overall' as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, IndicatorName
	, SUM(Numerator)
	, SUM(Denominator)
	, 1.0* SUM(Numerator)/ SUM(Denominator) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'iCareMart adjusted' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, 'readmissions rate' as 'Units'
	FROM #tnr_readmits3
	WHERE Program not in ('Mental Health & Addictions Ser','Mental Hlth & Substance Use')
	GROUP BY IndicatorId
	, CASE WHEN facility='RHS' THEN 'Richmond Hospital' ELSE NULL END
	, FiscalPeriodEndDate
	, FiscalPeriodLong
	, IndicatorName
	;
	GO

	--compute traget using last year as a baseline average
	IF OBJECT_ID('tempdb.dbo.#TNR_ID32_ID33_targets') is not null DROP TABLE #TNR_ID32_ID33_targets;
	GO

	SELECT LEFT(TimeFrameLabel,4) as 'FiscalYear'
	, indicatorID
	, Facility
	, Program
	, 1.0*SUM(numerator)/SUM(denominator) as 'Target'
	INTO #TNR_ID32_ID33_targets
	FROM #TNR_ID32_ID33
	GROUP BY LEFT(TimeFrameLabel,4)
	, indicatorID
	, Facility
	, Program
	;
	GO

	-- update targets
	UPDATE X
	SET X.[Target] = Y.[Target]
	FROM #TNR_ID32_ID33 as X
	INNER JOIN #TNR_ID32_ID33_targets as Y
	ON X.Facility=Y.Facility	--same facility
	AND X.Program=Y.Program		--same program
	AND X.IndicatorID=Y.IndicatorID
	AND CAST(LEFT(X.TimeFrameLabel,4) as int) = CAST(Y.FiscalYear as int) +1 --last fiscal year
	WHERE Y.[Target] is not null
	;
	GO

-----------------------------------------------
-- ID34 Average Number of Acute Mental Health Beds Occupied
-----------------------------------------------
	/*
	Purpose: To compute the average number of acute mental health beds occupied.
	Author: Hans Aisake
	Date Created: August 20, 2019
	Date Updated: Feb 23, 2021
	Inclusions/Exclusions:
		- true inpatient records only
		- excludes newborns
	Comments:
		- switched over to a finance based methodology
		- average census in RPEU and R2W / # of funded beds
	
	*/

	----------------------------------
	-- Finance Definition
	----------------------------------
	----pull IP days by program
	IF OBJECT_ID('tempdb.dbo.#TNR_MHSU_Census') is not null DROP TABLE #TNR_MHSU_Census;
	GO

	SELECT '34' as 'IndicatorID'
	, 'Richmond' as 'Facility'
	, ProgramDesc as 'Program'
	, FiscalPeriodEndDate as 'TimeFrame'
	, FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Average Number of Acute Mental Health Beds Occupied' as 'IndicatorName' 
	, ActualCensusDays as 'Numerator'
	, DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate ) +1 as 'Denominator'
	, CEILING(1.0*ActualCensusDays / DATEDIFF(day, fiscalperiodstartdate, fiscalperiodenddate ) ) as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, CAST(NULL as float) as 'Target'	--funded beds
	, 'ADTCMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory' 
	, '# beds' as 'Units'
	INTO #TNR_MHSU_Census
	FROM #TNR_inpatientDaysPGRM as X
	WHERE EntityDesc='Richmond Health Services' --richmond only
	AND ProgramDesc = 'Mental Hlth & Substance Use' --MHSU only
	;
	GO

	--------------------------
	---- ADTC Definition
	--------------------------

	----create a table with the funded bed numbers for mental health
	--IF OBJECT_ID('tempdb.dbo.#TNR_MHSU_FundedBeds') is not null DROP TABLE #TNR_MHSU_FundedBeds;
	--GO

	--CREATE TABLE #TNR_MHSU_FundedBeds
	--( FiscalYear int
	--  , FAcility varchar(255)
	--  , NursingUnitCode varchar(10)
	--  , FundedBeds int
	--)
	--GO

	---- R2W has had 18 beds for a long time
	---- RPEU has had 4 beds for a long time
	--INSERT INTO #TNR_MHSU_FundedBeds VALUES
	--(2020, 'Richmond Hospital', 'R2W',18),
	--(2020, 'Richmond Hospital', 'RPEU',4),
	--(2019, 'Richmond Hospital', 'R2W',18),
	--(2019, 'Richmond Hospital', 'RPEU',4),
	--(2018, 'Richmond Hospital', 'R2W',18),
	--(2018, 'Richmond Hospital', 'RPEU',4),
	--(2017, 'Richmond Hospital', 'R2W',18),
	--(2017, 'Richmond Hospital', 'RPEU',4),
	--(2016, 'Richmond Hospital', 'R2W',18),
	--(2016, 'Richmond Hospital', 'RPEU',4)
	--;
	--GO

	----pull census from R2W and RPEU and compute the average census per period	
	--IF OBJECT_ID('tempdb.dbo.#TNR_MHSU_Census') is not null DROP TABLE #TNR_MHSU_Census;
	--GO

	----get census of RPEU and R2W
	--SELECT '34' as 'IndicatorID'
	--, FacilityLongName as 'Facility'
	--, Map.NewProgram as 'Program'
	--, D.FiscalPeriodEndDate as 'TimeFrame'
	--, D.FiscalPeriodLong as 'TimeFrameLabel'
	--, 'Fiscal Period' as 'TimeFrameType'
	--, 'Average Number of Acute Mental Health Beds Occupied' as 'IndicatorName' 
	--, SUM(1) as 'Numerator'
	--, DATEDIFF(day, MAX(D.fiscalperiodstartdate), MAX(D.fiscalperiodenddate) ) +1 as 'Denominator'
	--, CEILING(1.0*SUM(1) / DATEDIFF(day, MAX(D.fiscalperiodstartdate), MAX(D.fiscalperiodenddate) ) ) as 'Value'
	--, 'Below' as 'DesiredDirection'
	--, 'D0' as 'Format'
	--, CAST(NULL as float) as 'Target'	--funded beds
	--, 'ADTCMart' as 'DataSource'
	--, 0 as 'IsOverall'
	--, 0 as 'Scorecard_eligible'
	--, 'True North Metrics' as 'IndicatorCategory' 
	--, '# beds' as 'Units'
	--INTO #TNR_MHSU_Census
	--FROM ADTCMart.adtc.vwCensusFact as ADTC
	--LEFT JOIN DSSI.dbo.RH_VisibilityWall_NU_PROGRAM_MAP_ADTC as MAP
	--ON ADTC.CensusDate BETWEEN MAP.StartDate AND MAP.EndDate		--active map dates
	--AND ADTC.NursingUnitCode=MAP.nursingunitcode	--same nursing unit
	--INNER JOIN #tnr_periods as D
	--ON ADTC.CensusDate BETWEEN D.FiscalPeriodStartDate AND D.FiscalPeriodEndDate
	--WHERE ADTC.nursingunitcode in ('RPEU','R2W') --mental health units only
	--AND ADTC.[Site]='RMD'
	--AND ADTC.AccountType in ('I', 'Inpatient', '391')	--the code is different for each facility. Richmond is Inpatient
	--AND ADTC.AccountSubtype in ('Acute')				--no exclusions other than inpatient
	--GROUP BY ADTC.FacilityLongName
	--, Map.NewProgram
	--, D.FiscalPeriodEndDate
	--, D.FiscalPeriodLong 
	--;
	--GO

	----add funded bed target levels
	--UPDATE X
	--SET [Target] = Y.FundedBeds
	--FROM #TNR_MHSU_Census as X
	--LEFT JOIN (	SELECT FiscalYear, Facility, SUM(FundedBeds) as 'FundedBeds' 
	--			FROM #TNR_MHSU_FundedBeds
	--			GROUP BY FiscalYear, Facility) as Y
	--ON CAST(LEFT(X.TimeFrameLabel,4) as int) = Y.FiscalYear		--same year
	--AND X.Facility=Y.Facility --same facility
	--;
	--GO
	
	-----------------------------
	--compute and store metric
	IF OBJECT_ID('tempdb.dbo.#TNR_ID34') IS NOT NULL DROP TABLE #TNR_ID34;
	GO

	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, TimeFrameType, IndicatorName, Numerator, Denominator, [Value], DesiredDirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	INTO #TNR_ID34
	FROM #TNR_MHSU_Census
	UNION
	SELECT IndicatorID, Facility, 'Overall' as 'Program', TimeFrame, TimeFrameLabel, TimeFrameType, IndicatorName, SUM(Numerator), SUM(Denominator), 1.0*SUM(Numerator)/SUM(Denominator), DesiredDirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_MHSU_Census
	GROUP BY IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, TimeFrameType, IndicatorName, DesiredDirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, units
	;
	GO

-----------------------------------------------
-- ID35 Not Available at this time % of Surgical Cases booked “In Turn” (FIFO) 
-----------------------------------------------
	/*
	Purpose: Pull Number of Surgical Cases Booked "In Turn" (FIFO)
	Author: Hans Aisake
	Date Created: 2019 August 28
	Date Modified: 
	Comments: Program is the surgery program or overall
	*/

	-- We do not store the data in DSSI at this time and thus cannot have this indicator here. You can find it in the workbook.
	-- G:\VCHDecisionSupport\Coastal_Richmond_SI\True North Metrics

-----------------------------------------------
-- ID36 % of Placement to Long-Term Care During Period from Richmond Acute & Richmond Community 
-- Goes into Excel
-----------------------------------------------
	--/*
	--Purpose: Pull % of placements to LTC from acute and community
	--Author: Hans Aisake
	--Date Created: 2019 September 3
	--Date Modified: 
	--Comments: Program is Home and Community Care
	---- The LTC team is not running the code to populate this table.
	--*/

	--IF OBJECT_ID('tempdb.dbo.#TNR_ID36_Excel') is not NULL DROP TABLE #TNR_ID36_Excel;
	--GO

	--SELECT 	'36' as 'IndicatorID'
	--, [Region] as 'Facility'
	--, (SELECT distinct program FROM #TNR_ID01 WHERE program like '%home%') as 'Program'
	--, LEFT(FiscalyearPeriod, 9) as 'FiscalYear'
	--, 'P' + RIGHT(FiscalYearPeriod, 2) as 'FiscalPeriod'
	--, Numerator
	--, Denominator
	--, Measure
	--, '% of Placement to Long-Term Care During Period from RH ' + [Client Location Group] as 'IndicatorName'
	--INTO #TNR_ID36_Excel
	--FROM DSSI.dbo.PriorityAccessIndicators
	--WHERE indicatorId =5	-- % of placements indicator
	--AND Region = 'Richmond'	-- richmond region
	--AND LEFT(FiscalyearPeriod, 9) in ( SELECT distinct TOP 2 LEFT(FiscalyearPeriod, 9) FROM DSSI.dbo.PriorityAccessIndicators ORDER BY LEFT(FiscalyearPeriod, 9) )
	--AND [Client Location Group] in ('Acute','Commuity')	--only want these groups for the TNM
	--;
	--GO
	
-----------------------------------------------
-- IDXX Number of Falls - Degree of Harm (2-5), No Harm (1), overall (1-5)
-----------------------------------------------
	--/*
	--Purpose: Pull Number of Falls for the true north metrics
	--Author: Hans Aisake
	--Co-author: Peter Kaloupis
	--Date Created: 2019 August 26
	--Date Modified: 
	--Comments: Programs are bassed on nursing units Updated programs and put them in a mapping table in DSSI.
	--*/

	----identify the time frames for the falls. Data comes by month and year, so I'm going to report it by month and year. Mapping it to FP is disingenuous
	--IF OBJECT_ID('tempdb.dbo.#TNR_falls_tf') IS NOT NULL DROP TABLE #TNR_falls_tf;	
	--GO

	--SELECT distinct TOP 48 [Year], [Month]
	--INTO #TNR_falls_tf
	--FROM [DSSI].[dbo].[RHFallsVisibilityWall]	--is null need to get this data back again.
	--ORDER BY [Year] DESC, [Month] DESC
	--;
	--GO

	----identify types of harm
	--IF OBJECT_ID('tempdb.dbo.#TNR_falls_harmtypes') IS NOT NULL DROP TABLE #TNR_falls_harmtypes; 
	--GO

	--CREATE TABLE #TNR_falls_harmtypes ( HarmFlag varchar(25));
	--INSERT INTO #TNR_falls_harmtypes 	VALUES ('Degree of Harm (2-5)'),('No Harm (NA & 1)'); 
	--GO

	----create place holder table to house falls
	--IF OBJECT_ID('tempdb.dbo.#TNR_falls_groupings') IS NOT NULL DROP TABLE #TNR_falls_groupings; 
	--GO

	--SELECT T.*,P.*,H.* 	
	--INTO #TNR_falls_groupings
	--FROM #TNR_falls_tf as T
	--CROSS JOIN  	(SELECT distinct [Director Programs] as 'Program' FROM DSSI.[dbo].[RH_VisibilityWall_QPS_FallsProgramMap]) as P
	--CROSS JOIN  	(SELECT * FROM #TNR_falls_harmtypes ) as H
	--;
	--GO
	
	----count number of falls resulting in harm or not harm by program
	--IF OBJECT_ID('tempdb.dbo.#TNR_falls') IS NOT NULL DROP TABLE #TNR_falls;
	--GO

	--SELECT M.[Director Programs] as 'Program'
	--,CASE WHEN F.[Degree of Harm] in ('1 - No harm', 'Not Applicable') then 'No Harm (NA & 1)' 
	--	  ELSE 'Degree of Harm (2-5)' 
	--END as 'HarmFlag'
	--, [Year]
	--, [Month]
	--, COUNT(*) as 'NumFallsCases'
	--INTO #TNR_falls
	--FROM [DSSI].[dbo].[RHFallsVisibilityWall] as F
	--LEFT JOIN DSSI.[dbo].[RH_VisibilityWall_QPS_FallsProgramMap] as M
	--ON F.[Responsible Program]=M.[Falls Responsible Programs]
	--WHERE F.[Originated HSDA]='richmond'
	--GROUP BY M.[Director Programs]
	--,CASE WHEN F.[Degree of Harm] in ('1 - No harm', 'Not Applicable') then 'No Harm (NA & 1)' 
	--	  ELSE 'Degree of Harm (2-5)' 
	--END
	--, [Year]
	--, [Month]
	--;
	--GO

	----compute falls data set
	--IF OBJECT_ID('tempdb.dbo.#TNR_IDXX_Falls') is not null DROP TABLE #TNR_IDXX_Falls;
	--GO

	----add harm
	--SELECT 
	--'Richmond' as 'Facility' 
	--, R.Program
	--, R.[Year]
	--, R.[Month]
	--, 'Degree of Harm (2-5)'  as 'HarmFlag'
	--, ISNULL(F.NumFallsCases,0) as 'Value'
	--INTO #TNR_IDXX_Falls
	--FROM #TNR_falls_groupings as R
	--LEFT JOIN #TNR_falls as F
	--ON R.[program]=F.[Program]
	--AND R.[HarmFlag]=F.[HarmFlag]
	--AND R.[Year] = F.[Year] 
	--AND R.[Month] = F.[Month]
	--WHERE R.HarmFlag='Degree of Harm (2-5)' 
	---- add overall harm
	--UNION
	--SELECT
	--'Richmond' as 'Facility' 
	--, 'Overall' as 'Program'
	--, R.[Year]
	--, R.[Month]
	--, 'Degree of Harm (2-5)'  as 'HarmFlag'
	--, SUM(ISNULL(F.NumFallsCases,0)) as 'Value'
	--FROM (SELECT distinct [Year], [Month], [HarmFlag] FROM #TNR_falls_groupings WHERE [HarmFlag]='Degree of Harm (2-5)' ) as R	--just distinct years, months, and harm
	--LEFT JOIN #TNR_falls as F
	--ON R.[HarmFlag]=F.[HarmFlag]
	--AND R.[Year] = F.[Year] 
	--AND R.[Month] = F.[Month]
	--GROUP BY  R.[Year]
	--, R.[Month]
	----add no harm
	--UNION
	--SELECT 'Richmond' as 'Facility' 
	--, R.Program
	--, R.[Year]
	--, R.[Month]
	--, 'No Harm (NA & 1)' as 'HarmFlag'
	--, ISNULL(F.NumFallsCases,0) as 'Value'
	--FROM #TNR_falls_groupings as R
	--LEFT JOIN #TNR_falls as F
	--ON R.[program]=F.[Program]
	--AND R.[HarmFlag]=F.[HarmFlag]
	--AND R.[Year] = F.[Year] 
	--AND R.[Month] = F.[Month]
	--WHERE R.HarmFlag='No Harm (NA & 1)'
	---- add overall no harm
	--UNION
	--SELECT 'Richmond' as 'Facility' 
	--, 'Overall' as 'Program'
	--, R.[Year]
	--, R.[Month]
	--, 'No Harm (NA & 1)' as 'HarmFlag'
	--, SUM(ISNULL(F.NumFallsCases,0)) as 'Value'
	--FROM (SELECT distinct [Year], [Month], [HarmFlag] FROM #TNR_falls_groupings WHERE [HarmFlag]='No Harm (NA & 1)') as R	--just distinct years, months, and harm
	--LEFT JOIN #TNR_falls as F
	--ON R.[HarmFlag]=F.[HarmFlag]
	--AND R.[Year] = F.[Year] 
	--AND R.[Month] = F.[Month]
	--GROUP BY  R.[Year]
	--, R.[Month]
	--;
	--GO

	----put data into a falls table
	--TRUNCATE TABLE DSSI.dbo.TRUE_NORTH_RICHMOND_FALLS; 
	--GO

	--INSERT INTO DSSI.dbo.TRUE_NORTH_RICHMOND_FALLS ( Facility, [Program], [year], [Month], [HarmFlag], [Value])
	--SELECT Facility, [Program], [year], [Month], [HarmFlag], [Value]
	--FROM #TNR_IDXX_Falls
	--;
	--GO

-------------------------------
-- Home Support (HS) Hours and % change from last year ID37 and ID38
------------------------------

	--get HS hours out of financemart
	IF OBJECT_ID('tempdb.dbo.#tnr_hsHours') is not null DROP TABLE #tnr_hsHours;
	GO

	SELECT D.FiscalPeriodLong
	, D.FiscalPeriodEndDate
	--, CASE WHEN FinSiteID in (655) THEN 'Richmond' WHEN FinSiteID in (....) THEN 'Vancouver' etc....
	, DATEDIFF(day, MAX(D.FiscalPeriodStartDate), MAX(D.FiscalPeriodEndDate) ) +1 as 'Days_in_Period'
	, 28.0*SUM( Gl.ActualAmt )/ (DATEDIFF(day, MAX(D.FiscalPeriodStartDate), MAX(D.FiscalPeriodEndDate) )+1) as 'Actual'
	, 28.0*SUM( Gl.BudgetAmt )/ (DATEDIFF(day, MAX(D.FiscalPeriodStartDate), MAX(D.FiscalPeriodEndDate) )+1) as 'Budget'
	INTO #tnr_hsHours
	FROM FinanceMart.[Finance].[GLAccountStatsFact] as GL
	LEFT JOIN FinanceMart.Dim.CostCenter as CC
	ON GL.CostCenterID=CC.CostCenterID
	INNER JOIN #tnr_periods as D							--filter to FP s to report on and to get labels; longer than normal because we need % change for ID38
	ON GL.FiscalPeriodEndDateID=D.FiscalPeriodEndDateID		--same fiscal period end date
	WHERE FinSiteID ='655' -- Richmond communit site code
	AND GLAccountCode in ( 'S830920', 'S901220' )	--HS hours accounts contracted and direct care
	AND GL.CostCenterID!=5155		--exclude CSIL
	GROUP BY D.FiscalPeriodLong
	, D.FiscalPeriodEndDate
	-- need to remove the CSIL cost center
	;
	GO

	--store HS hours
	IF OBJECT_ID('tempdb.dbo.#TNR_ID37') IS NOT NULL DROP TABLE #TNR_ID37;
	GO

	SELECT '37' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, (SELECT TOP 1 Program FROM #TNR_ID01 WHERE [Program] like '%home%' ) as 'Program' 
	, X.FiscalPeriodEndDate as 'TimeFrame'
	, X.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, '# of HS Hours excl. CSIL' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, actual as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, Budget as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# hours' as 'Units'
	INTO #TNR_ID37
	FROM #tnr_hsHours as X
	INNER JOIN #TNR_FPReportTF as Y
	ON X.FiscalPeriodLong = Y.FiscalPeriodLong
	--
	UNION
	SELECT '37' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, 'Overall' as 'Program' 
	, X.FiscalPeriodEndDate as 'TimeFrame'
	, X.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, '# of HS Hours excl. CSIL' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, actual as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'D0' as 'Format'
	, Budget as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '# hours' as 'Units'
	FROM #tnr_hsHours as X
	INNER JOIN #TNR_FPReportTF as Y
	ON X.FiscalPeriodLong = Y.FiscalPeriodLong
	GO

	--compute % of HS hours changed from last year
	IF OBJECT_ID('tempdb.dbo.#tnr_hsHoursChanged') is not null DROP TABLE #tnr_hsHoursChanged;
	GO

	SELECT X.FiscalPeriodLong, X.FiscalPeriodEndDate, X.Days_in_Period
	, 1.0*(X.Actual - Y.Actual) / Y.Actual as 'Actual'
	, 1.0*(X.Budget - Y.Budget) / Y.Budget as 'Budget'
	INTO #tnr_hsHoursChanged
	FROM #tnr_hsHours as X					--current year
	INNER JOIN #tnr_hsHours as Y			--last year , requires both years for computation
	ON CAST(LEFT(X.FiscalPeriodLong,4) as int) = (CAST(LEFT(Y.FiscalPeriodLong,4) as int)+1)		--current year = last year
	AND RIGHT(X.FiscalPeriodLong,2) = Right(Y.FiscalPeriodLong,2)	--same fiscal period
	;
	GO

	--store HS hours % change
	IF OBJECT_ID('tempdb.dbo.#TNR_ID38') IS NOT NULL DROP TABLE #TNR_ID38;
	GO

	SELECT '38' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, (SELECT TOP 1 Program FROM #TNR_ID01 WHERE [Program] like '%home%' ) as 'Program' 
	, X.FiscalPeriodEndDate as 'TimeFrame'
	, X.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, '% changed of HS Hours from same period prior fiscal year excl. CSIL' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, actual as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	, Budget as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 0 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '% change' as 'Units'
	INTO #TNR_ID38
	FROM #tnr_hsHoursChanged as X
	INNER JOIN #TNR_FPReportTF as Y
	ON X.FiscalPeriodLong = Y.FiscalPeriodLong
	--
	UNION
	SELECT '38' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, 'Overall' as 'Program' 
	, X.FiscalPeriodEndDate as 'TimeFrame'
	, X.FiscalPeriodLong as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, '% changed of HS Hours from same period prior fiscal year excl. CSIL' as 'IndicatorName'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, actual as 'Value'
	, 'Below' as 'DesiredDirection'
	, 'P1' as 'Format'
	, Budget as 'Target'
	, 'FinanceMart' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'True North Metrics' as 'IndicatorCategory'
	, '% change' as 'Units'
	FROM #tnr_hsHoursChanged as X
	INNER JOIN #TNR_FPReportTF as Y
	ON X.FiscalPeriodLong = Y.FiscalPeriodLong
	GO

-------------------------------
--  Clostridium difficile infection rate per 10,000 patient days  ID39
------------------------------
	/*
	Purpose: Pull data from BSI for the BSC indicator. Clostridium difficile infection rate per 10,000 patient days
	Author: Hans Aisake
	Date Created: Sept 17, 2019
	Inclusions/exclusions:
	Comments: new indicatorSummaryFactID's show up each year.
	Indicator id is 9.
	Update Log:
	*/

	--join the relevant BSI data tables
	IF OBJECT_ID('tempdb.dbo.#BSI_CDI') IS NOT NULL DROP TABLE #BSI_CDI

	--factdatarowtypeid=1 for actuals, 2 for others
	SELECT '39' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, 'Overall' as 'Program'
	, REPLACE(I.[SETRptIndLongName], ' (i)','') as 'IndicatorName'
	, ISF.EntityIndicatorID
	, ISF.FullFiscalYear
	, ISF.FY_YTD
	, ISF.FP1
	, ISF.FP2
	, ISF.FP3
	, ISF.FP4
	, ISF.FP5
	, ISF.FP6
	, ISF.FP7
	, ISF.FP8
	, ISF.FP9
	, ISF.FP10
	, ISF.FP11
	, ISF.FP12
	, ISF.FP13
	, ISF.FactDataRowTypeID
	--, CASE	WHEN E.Entity = 'Van (VCH)' THEN 'Vancouver'
	--		WHEN E.Entity = 'Rmd' THEN 'Richmond'
	--		ELSE E.Entity
	--END as 'CommunityRegion' 
	INTO #BSI_CDI
	FROM BSI.BSI.IndicatorSummaryFact as ISF
	LEFT JOIN BSI.dim.EntityIndicator as EI
	ON ISF.EntityIndicatorID=EI.EntityIndicatorID
	LEFT JOIN BSI.dim.Entity as E
	ON EI.EntityID=E.EntityID
	LEFT JOIN BSI.dim.Indicator as I
	ON ISF.IndicatorID =I.IndicatorID
	WHERE ISF.IndicatorID=9 -- CDI indicator
	AND E.Entity = 'Rmd'	-- richmond only; could turn off to make this regional
	;
	GO

	--restructure the data from BSI
	IF OBJECT_ID('tempdb.dbo.#tmpID39') IS NOT NULL DROP TABLE #tmpID39;

	--pull the different time ranges of the data and reorder it into a table with a useable format
	--unions FP1, FP2, FP3, FP4, FP5, FP6, FP7, FP8, FP9, FP10, FP11, FP12, FP13
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP1/100.0 as 'Value'
	, B2.FP1/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-01' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	INTO #tmpID39
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP1 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP2/100.0 as 'Value'
	, B2.FP2/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-02' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP2 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP3/100.0 as 'Value'
	, B2.FP3/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-03' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP3 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP4/100.0 as 'Value'
	, B2.FP4/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-04' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP4 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP5/100.0 as 'Value'
	, B2.FP5/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-05' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP5 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP6/100.0 as 'Value'
	, B2.FP6/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-06' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP6 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP7/100.0 as 'Value'
	, B2.FP7/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-07' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP7 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP8/100.0 as 'Value'
	, B2.FP8/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-08' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP8 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP9/100.0 as 'Value'
	, B2.FP9/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-09' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP9 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP10/100.0 as 'Value'
	, B2.FP10/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-10' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP10 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP11/100.0 as 'Value'
	, B2.FP11/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-11' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP11 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP12/100.0 as 'Value'
	, B2.FP12/100.0 as 'Target'
	, CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-12' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP12 is not NULL	-- actual value is provided
	UNION
	SELECT B1.IndicatorID, B1.Facility, B1.Program, B1.IndicatorName
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, B1.FP13/100.0 as 'Value'
	, B2.FP13/100.0 as 'Target'
	,CAST(CAST(LEFT(B1.FullFiscalYear,4) as int) +1 as varchar(20)) + '-13' as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	--, B1.CommunityRegion
	FROM #BSI_CDI as B1
	LEFT JOIN #BSI_CDI as B2
	ON B1.EntityIndicatorID=B2.EntityIndicatorID 
	AND B1.FullFiscalYear=B2.FullFiscalYear
	WHERE B1.FactDataRowTypeID=1 AND B2.FactDataRowTypeID=2	--to get actual and target next to each other; tricky to put it into the join
	AND B1.FP13 is not NULL	-- actual value is provided
	;
	GO

	--add timeframe and other missing attributes and store into the final result table
	IF OBJECT_ID('tempdb.dbo.#TNR_ID39') IS NOT NULL DROP TABLE #TNR_ID39;

	SELECT X.IndicatorID
	, X.Facility
	, X.Program
	, D.FiscalPeriodEndDate as 'TimeFrame'
	, X.TimeFrameLabel
	, X.TimeFrameType
	, X.IndicatorName
	, X.Numerator
	, X.Denominator
	, X.[Value]
	, 'Below' as 'DesiredDirection'
	, 'D1' as 'Format'
	, X.[Target]
	, 'BSC' as 'DataSource'
	, 1 as 'IsOverall'
	, 0 as 'Scorecard_eligible'
	, 'Richmond Custom' as 'IndicatorCategory'
	, '# cases per 10,000 pt. days' as 'Units'
	INTO #TNR_ID39
	FROM #tmpID39 as X
	INNER JOIN #TNR_FPReportTF as D			--filter out too old data
	ON X.TimeFrameLabel=D.FiscalPeriodLong
	;
	GO

	----Current YTD value if you need it
	--SELECT IndicatorName, FullFiscalYear, Facility, CASE WHEN FactDataRowTypeID=1 THEN 'Actual'	ELSE 'Target' END as 'Type', FY_YTD
	--FROM #BSI_CDI
	--WHERE FullFiscalYear =  (SELECT MAX(Fullfiscalyear) FROM #BSI_CDI)

	-----------------------------------------------
	--ID 40 ALC Rate for Medicing, Hospitalists, and Palliative 
	-----------------------------------------------
		/*
		Purpose: To compute the ALC rate for medicine patients seen by hospitalists, palliative care, and other medicine specialties
		Author: Hans Aisake
		Date Created: Set 17, 2019
		Date Updated: 
		Inclusions/Exclusions:
			- Exclude TCU patients where account sub type is extended care or something like EC; <elaborate>
		Comments:
			- to hide from the front sheet of the scorecard?
			- the mapping to services is not accurate enough for history =/
		*/

		--preprocess Census data and identify reporting time frames
		IF OBJECT_ID('tempdb.dbo.#tnr_raw40') IS NOT NULL DROP TABLE #tnr_raw40;
		GO

		--I wrote the computations in the complex way in an attempt to save a few seconds of computation; I am not sure I succeeded.
		SELECT 	D.FiscalPeriodLong
		, D.FiscalPeriodEndDate
		, C.AccountNum
		, C.FacilityLongName as 'Facility'
		, CASE	WHEN H.DrCode is not null THEN 'RHS Hospitalist'
				WHEN H.DrCode is null AND C.NursingUnitCode in ('R3SP') THEN 'Palliative'
				WHEN H.DrCode is null AND C.NursingUnitCode not in ('RPEU', 'RICU', 'R2W', 'R3SP', 'R3N', 'RHAU', 'R3BC', 'RSCN', 'RSDC') THEN 'Acute Medicine'
				ELSE 'Non-Acute Medicine'
		END as 'Medical_Service'
		, H.DrCode
		, C.NursingUnitCode
		, CASE WHEN patientservicecode like 'AL[0-9]' or patientservicecode like 'A1[0-9]' THEN 1 ELSE 0 END as 'ALC_Flag'
		INTO #TNR_raw40
		FROM ADTCMart.adtc.vwCensusFact as C
		INNER JOIN #TNR_FPReportTF as D	 --only keep periods we care about
		ON C.CensusDate BETWEEN D.FiscalPeriodStartDate AND D.FiscalPeriodEndDate
		LEFT JOIN DSSI.dbo.Hospitalists as H	--flag hospitalist patients
		ON C.AttendDoctorCode = H.DrCode
		--AND C.CensusDate BETWEEN H.StartDate AND H.EndDate	-- why aren't these populated =/
		WHERE C.AccountType in ('Inpatient')		--true inpatients
		AND C.AccountSubtype ='Acute'				--true inpatients; remove TCU/EC etc...
		AND [Site]='RMD'							--richmond only
		AND C.CensusDAte >='2019-01-01'	--cut off history because criterion aren't correct enoguh to go back farther
		AND NursingUnitCode not like 'M%'
		AND NursingUnitCode not in ('RPEU', 'RICU', 'R2W', 'R3N', 'RHAU', 'R3BC', 'RSCN', 'RSDC')	--only medicine units
		;
		GO

		--generate indicators and store the data
		IF OBJECT_ID('tempdb.dbo.#TNR_ID40') IS NOT NULL DROP TABLE #TNR_ID40;
		GO

		--services by hospitalist, IM, etc....
		SELECT 	'40' as 'IndicatorID'
		, Facility
		, Medical_Service as 'Program'
		, FiscalPeriodEndDate as 'TimeFrame'
		, FiscalPeriodLong as 'TimeFrameLabel'
		, 'Fiscal Period' as 'TimeFrameType'
		, 'ALC Rate (Acute Medicine)' as 'IndicatorName'
		, COUNT(distinct CASE WHEN ALC_Flag=1 THEN AccountNum ELSE NULL END) as 'Numerator'
		, COUNT(distinct AccountNum ) as 'Denominator'
		, 1.0* COUNT(distinct CASE WHEN ALC_Flag=1 THEN AccountNum ELSE NULL END) / COUNT(distinct AccountNum ) as 'Value'
		, 'Below' as 'DesiredDirection'
		, 'P1' as 'Format'
		,  CAST(NULL as float) as 'Target'
		, 'ADTC-Census' as 'DataSource'
		, 0 as 'IsOverall'
		, 1 as 'Scorecard_eligible'
		, 'Exceptional Care' as 'IndicatorCategory'
		, 'ALC rate' as 'Units'
		INTO #TNR_ID40
		FROM #TNR_raw40
		GROUP BY Facility
		, Medical_Service
		, FiscalPeriodEndDate
		, FiscalPeriodLong 
		--add overall indicator
		UNION
		SELECT 	'40' as 'IndicatorID'
		, Facility
		, 'Overall' as 'Program'
		, FiscalPeriodEndDate as 'TimeFrame'
		, FiscalPeriodLong as 'TimeFrameLabel'
		, 'Fiscal Period' as 'TimeFrameType'
		, 'ALC Rate (Acute Medicine)' as 'IndicatorName'
		, COUNT(distinct CASE WHEN ALC_Flag=1 THEN AccountNum ELSE NULL END) as 'Numerator'
		, COUNT(distinct AccountNum ) as 'Denominator'
		, 1.0* COUNT(distinct CASE WHEN ALC_Flag=1 THEN AccountNum ELSE NULL END) / COUNT(distinct AccountNum ) as 'Value'
		, 'Below' as 'DesiredDirection'
		, 'P1' as 'Format'
		,  CAST(NULL as float) as 'Target'
		, 'ADTC-Census' as 'DataSource'
		, 1 as 'IsOverall'
		, 1 as 'Scorecard_eligible'
		, 'Exceptional Care' as 'IndicatorCategory'
		, 'ALC rate' as 'Units'
		FROM #TNR_raw40
		GROUP BY Facility
		, FiscalPeriodEndDate
		, FiscalPeriodLong 
		;
		GO

		--ALC targets for richmond overall from BSI to match BSC similar to the program indicator
		IF OBJECT_ID('tempdb.dbo.#TNR_ID40_targets') IS NOT NULL DROP TABLE #TNR_ID40_targets;
		GO

		SELECT LEFT(FullFiscalYear,2)+RIGHT(FullFiscalYear,2) as 'FiscalYear'
		, CASE WHEN EntityIndicatorID = 35 THEN 'Richmond Hospital'
			   WHEN EntityIndicatorID = 34 THEN 'Vancouver General Hospital'
			   WHEN EntityIndicatorID = 33 THEN 'Overall'
			   ELSE 'Unmapped'
		END as 'Facility'
		, [FY_YTD]/100 as 'Target'
		INTO #TNR_ID40_targets
		FROM BSI.[BSI].[IndicatorSummaryFact] 
		WHERE indicatorID=5		--ALC indicator on BSC as of 20190801
		and EntityIndicatorID=35 --richmond overall
		and FactDataRowTypeID=2 --target data
		AND [FY_YTD]  is not null
		;
		GO

		-- update targets
		UPDATE X
		SET [Target] = Y.[Target]
		FROM #TNR_ID40 as X
		INNER JOIN #TNR_ID40_targets as Y
		ON X.Facility=Y.Facility	--same facility
		AND LEFT(X.TimeFrameLabel,4) = Y.FiscalYear --same fiscal year
		--AND X.Program=Y.Program	; no program in BSI apply blanket rate target to all services
		;
		GO

--------------------------------
-- ID placeholder
--------------------------------

	IF OBJECT_ID('tempdb.dbo.#TNR_FAKE') is not null DROP TABLE #TNR_FAKE;
	GO

	--Create a data set to hold the placeholder indicator rows for the summary page etc..
	SELECT TOP 1 '08' as 'IndicatorID'
	, 'Richmond Hospital' as 'Facility'
	, 'Overall' as 'Program'
	, MAX(TimeFrame) as 'TimeFrame'
	, MAX(TimeFrameLabel) as 'TimeFrameLabel'
	, 'Fiscal Period' as 'TimeFrameType'
	, 'Discharges actual vs. predicted' as 'IndicatorName'
	, CAST(NULL as float) as 'Numerator'
	, CAST(NULL as float) as 'Denominator'
	, CAST(NULL as float) as 'Value'
	, 'Above' as 'DesiredDirection'
	, 'D1' as 'Format'
	, CAST(NULL as float) as 'Target'
	, 'Placeholder' as 'DataSource'
	, 1 as 'IsOverall'
	, 1 as 'Scorecard_eligible'
	, 'Exceptional Care' as 'IndicatorCategory'
	, 'discharge variance' as 'Units'
	INTO #TNR_FAKE
	FROM #TNR_ID01
	;
	GO

--------------------------------
--- Consolidate Indicators 
-------------------------------
	
	--union the results
	IF OBJECT_ID('tempdb.dbo.#TNR_FinalUnion') is not NULL DROP TABLE #TNR_FinalUnion;
	GO
	
	--put the new data into the table
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	INTO #TNR_FinalUnion
	FROM #TNR_ID01
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID01
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID02
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID03
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID04
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID05
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID06
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID07
	--UNION
	--SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	--FROM #TNR_ID08
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID09
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID10
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID11
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID12
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID13
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID14
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID15
	UNION
	SELECT IndicatorID, Facility, LoggedMainsurgeonSpecialty, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID16
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID17
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID18
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID19
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID20
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID21
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID22
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_IDHHDASH
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID31
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID32_ID33
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID34
	--UNION
	--SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	--FROM #TNR_ID35
	--UNION
	--SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	--FROM #TNR_ID36
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID37
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID38
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID39
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_ID40
	--add fake rows to populate summary page
	UNION
	SELECT IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units
	FROM #TNR_FAKE
	;
	GO

	-----------------------------------
	-- Identify which programs charts will be shown on the scorecard 
	-----------------------------------
	ALTER TABLE #TNR_FinalUnion
	ADD Hide_Chart int;
	GO

	UPDATE #TNR_FinalUnion
	SET Hide_Chart=1;
	GO

	IF OBJECT_ID('tempdb.dbo.#showCharts') is not null drop table #showCharts;
	GO

	-- Keep 5 largest programs by indicator and facility where program is not unknown for the lastest timeframe for each indicator
	SELECT distinct Z.IndicatorID, Z.Facility, Z.Program
	INTO #showCharts
	FROM (
		-- where denominator is available
		SELECT ROW_NUMBER() OVER(Partition by X.IndicatorId, X.facility ORDER BY X.Denominator DESC) as 'rn'
		, X.*
		FROM #TNR_FinalUnion as X
		INNER JOIN (SELECT IndicatorId, Facility, MAX(timeframe) as 'MaxTimeFrame' FROM #TNR_FinalUnion GROUP BY IndicatorId, Facility) as Y
		ON X.IndicatorID=Y.IndicatorID 
		AND X.Facility=Y.Facility 
		AND X.TimeFrame=Y.MaxTimeFrame
		WHERE Denominator is not NULL
		AND IsOverall=0
		AND Program not like '%unallocated%' --always remove these programs from being shown
		AND Program not in ('Unknown')	--always remove these programs from being shown
		AND Scorecard_eligible=1 	--only  for scorecard eligable indicators
		-- where denominator is not available
		UNION
		SELECT ROW_NUMBER() OVER(Partition by A.IndicatorId, A.facility ORDER BY A.[Value] DESC) as 'rn'
		, A.*
		FROM #TNR_FinalUnion as A
		INNER JOIN (SELECT IndicatorId, Facility, MAX(timeframe) as 'MaxTimeFrame' FROM #TNR_FinalUnion GROUP BY IndicatorId, Facility) as B
		ON A.IndicatorID=B.IndicatorID 
		AND A.Facility=B.Facility 
		AND A.TimeFrame=B.MaxTimeFrame
		WHERE Denominator is NULL
		AND IsOverall=0
		AND Program not like '%unallocated%' --always remove these programs from being shown
		AND Program not in ('Unknown')	--always remove these programs from being shown
		AND Scorecard_eligible=1 	--only  for scorecard eligable indicators
	) Z
	WHERE rn <=5
	OR  IndicatorID='16'
	;
	GO


	--There are lots of programs that aren't the typical ones not getting flagged
	UPDATE X
	SET X.hide_chart = 0
	FROM #TNR_FinalUnion as X
	LEFT JOIN #showCharts as Y
	ON X.IndicatorId=Y.IndicatorID
	AND X.Facility=y.Facility
	AND X.Program = Y.Program
	WHERE X.Scorecard_eligible=1
	AND (Y.IndicatorID is not null
	OR x.Program in ('Overall') )
	;
	GO

	-----------------------------------
	-- Timeseries version
	-----------------------------------
		TRUNCATE TABLE DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS;
		GO

		INSERT INTO DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS (IndicatorID, Facility, Program, TimeFrame, TimeFrameLabel, timeFrameType, IndicatorName, Numerator, Denominator, [Value], Desireddirection, [Format], [Target], DataSource, IsOverall, Scorecard_eligible, IndicatorCategory, Units, Hide_Chart)
		SELECT * FROM #TNR_FinalUnion
		;
		GO

	------------------------------
	-- for the scorecard front page
	------------------------------

	--WITH mostRecent as (
	--SELECT distinct IndicatorName
	--, Program
	--, MAX(timeframe) as 'LatestTimeFrame'
	--FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS
	--WHERE (indicatorID not in (16,40) and program in ('Emerg & Critical Care','Home & Community Care','Medicine Services','Mental Hlth & Substance Use','Overall','Surgery & Procedural Care','Pop & Family Hlth & Primary Cr') )
	--OR (indicatorID=16 AND program='Overall')	--don't pull surgical programs
	--GROUP BY IndicatorName
	--, Program
	--)

	--SELECT distinct X.*
	--FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS as X
	--INNER JOIN mostRecent  as Y
	--ON  X.TimeFrame=Y.LatestTimeFrame
	--AND X.Program=Y.Program
	--AND X.IndicatorName=Y.IndicatorName
	--OR  X.indicatorID in ('08')
	--WHERE X.Program not in ('Unknown')
	--AND X.Scorecard_eligible=1
	----AND 1 = (CASE WHEN @Version ='True North Scorecard' THEN X.Scorecard_eligible ELSE 1 END )
	--ORDER BY IndicatorID ASC, Program ASC

	------------------------------------
	-- Year over year version
	-----------------------------------
		IF OBJECT_ID('tempdb.dbo.#TNR_FinalUnion_Mod') is not null DROP TABLE #TNR_FinalUnion_Mod;
		GO

		SELECT * INTO #TNR_FinalUnion_Mod FROM #TNR_FinalUnion;
		GO
		
			--add on the time frame year values
		ALTER TABLE #TNR_FinalUnion_Mod
		ADD TimeFrameYear varchar(4), TimeFrameUnit varchar(10)
		;
		GO

		UPDATE #TNR_FinalUnion_Mod
		SET TimeFrameYear = CAsE WHEN timeFrameType='Fiscal Period'  THEN LEFT(TimeFrameLabel,4)  
								 WHEN timeFrameType='Fiscal Quarter' THEN LEFT(TimeFrameLabel,4)
								 WHEN timeFrameType='FQ HH'  THEN LEFT(TimeFrameLabel,4)  
								 ELSE 1900
							END
		, TimeFrameUnit = CAsE WHEN timeFrameType='Fiscal Period'  THEN 'P'+RIGHT(TimeFrameLabel,2)  
							   WHEN timeFrameType='Fiscal Quarter' THEN 'FQ'+RIGHT(TimeFrameLabel,2) 
							   WHEN timeFrameType='FQ HH' THEN 'FQ'+RIGHT(TimeFrameLabel,2) 
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
		SELECT distinct IndicatorID, IndicatorName, Facility, Program, [FORMAT], DataSource, Scorecard_eligible, [TimeFrameType], DesiredDirection
		, CAST(MAX(TimeFrameYear) as int) as 'LatestYear'
		, MAX(TimeFrameYear) -1  as 'LastYear'
		, MAX(TimeFrameYear) -2  as 'TwoYearsAgo'
		, CAST( MAX(TimeFrameYear)-1 as varchar(9) ) +'/' + CAST( MAX(TimeFrameYear) as varchar(9))  as 'LatestYearLabel'
		, CAST( MAX(TimeFrameYear)-2 as varchar(9) ) +'/' + CAST( MAX(TimeFrameYear)-1 as varchar(9))  as 'LastYearLabel'
		, CAST( MAX(TimeFrameYear)-3 as varchar(9) ) +'/' + CAST( MAX(TimeFrameYear)-2 as varchar(9))  as 'TwoYearsAgoLabel'
		, units
		FROM #TNR_FinalUnion_Mod 
		GROUP BY IndicatorID, IndicatorName, Facility, Program, [FORMAT], DataSource, Scorecard_eligible, [TimeFrameType], DesiredDirection, units
		) as X
		LEFT JOIN
		(SELECT distinct IndicatorID, TimeFrameUnit FROM #TNR_FinalUnion_Mod) as Y
		ON X.IndicatorID=Y.IndicatorID
		;
		GO

		--manipulate the structure into an excel like structure 
		IF OBJECT_ID('tempdb.dbo.#TNR_FinalUnion2') is not null DROP TABLE #TNR_FinalUnion2;
		GO

		SELECT P.IndicatorID
		, Cast( P.IndicatorName as varchar(255)) as 'IndicatorName'
		, P.Facility
		, P.Program
		, P.[Format]
		, CAST( P.DataSource as varchar(255)) as 'DataSource'
		, P.Scorecard_eligible
		, P.[TimeFrameType]
		, P.DesiredDirection
		, P.TimeFrameUnit
		, P.LatestYear
		, P.LastYear
		, P.TwoYearsAgo
		, P.LatestYearLabel
		, P.LastYearLabel
		, P.TwoYearsAgoLabel
		, X.[Target], X.[Value] as 'LatestYear_Value',  Y.[Value] as 'LastYear_Value', Z.[Value] as 'TwoYearsAgo_Value'
		, P.units
		, A.Hide_Chart
		INTO #TNR_FinalUnion2
		FROM #skeleton as P
		LEFT JOIN #TNR_FinalUnion_Mod as X	--get latest year value
		ON P.IndicatorID = X.IndicatorID AND P.Facility = X.Facility AND P.Program  = X.Program AND P.LatestYear  = X.TimeFrameYear AND P.TimeFrameUnit = X.TimeFrameUnit
		LEFT JOIN #TNR_FinalUnion_Mod as Y	--get latest year value
		ON P.IndicatorID = Y.IndicatorID AND P.Facility = Y.Facility AND P.Program  = Y.Program AND P.LastYear    = Y.TimeFrameYear AND P.TimeFrameUnit = Y.TimeFrameUnit
		LEFT JOIN #TNR_FinalUnion_Mod as Z	--get latest year value
		ON P.IndicatorID = Z.IndicatorID AND P.Facility = Z.Facility AND P.Program  = Z.Program AND P.TwoYearsAgo = Z.TimeFrameYear AND P.TimeFrameUnit = Z.TimeFrameUnit
		LEFT JOIN  (SELECT distinct Q.IndicatorID, Q.Facility, Q.Program , Q.Hide_Chart 
					FROM #TNR_FinalUnion as Q
					INNER JOIN ( SELECT IndicatorId, Facility, MAX(timeframe) as 'MaxTimeFrame' FROM #TNR_FinalUnion GROUP BY IndicatorId, Facility) as R
					ON Q.IndicatorID=R.IndicatorID AND Q.Facility=R.Facility AND Q.TimeFrame=R.MaxTimeFrame
				   ) as A
		ON P.IndicatorID = A.IndicatorID AND P.Facility = A.Facility AND P.Program  = A.Program
		--WHERE X.[Value] is not null OR Y.[Value] is not null OR Z.[Value] is not null
		;
		GO

		--fill in the target series for the current year
		UPDATE X 
		SET [Target]=Y.[Target]
		FROM #TNR_FinalUnion2 as X
		LEFT JOIN ( SELECT distinct indicatorId, facility, program, [Target] FROM #TNR_FinalUnion2 WHERE [Target] is not null) as Y
		ON X.IndicatorID=Y.IndicatorID AND X.Facility=Y.Facility AND X.Program=Y.Program
		WHERE X.[Target] is null
		;
		GO

		--save the results to the YOY table
		TRUNCATE TABLE DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS_YOY] ;
		GO

		INSERT INTO DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS_YOY] ([IndicatorID],IndicatorName, [Facility], [Program], [FORMAT], DataSource, Scorecard_eligible, [TimeFrameType],DesiredDirection, [TimeFrameUnit], LatestYear, LastYear, TwoYearsAgo, LatestYearLabel, LastYearLabel, TwoYearsAgoLabel, [Target], [LatestYear_Value], [LastYear_Value], [TwoYearsAgo_Value], units, hide_chart )
		SELECT * FROM #TNR_FinalUnion2 
		;
		GO

		--------------------
		-- For YOY version
		--------------------
		--mastertablemostrecent ; same as the time series version

		----master table all
		--SELECT X.*
		--, CASE	WHEN X.IndicatorId not in ('04') THEN ROUND(Y.[Y-Axis_Max],Y.RoundPrecision)
		--		ELSE ROUND(Z.[Y-Axis_Max],Z.RoundPrecision) 
		--END as 'Y-Axis_Max'
		--, CASE	WHEN X.IndicatorId not in ('04') THEN ROUND(Y.[Y-Axis_Min],Y.RoundPrecision)
		--		ELSE ROUND(Z.[Y-Axis_Min],Z.RoundPrecision) 
		--END as 'Y-Axis_Min'
		--FROM [DSSI].[dbo].[TRUE_NORTH_RICHMOND_INDICATORS_YOY] as X
		--LEFT JOIN (
		--	SELECT distinct indicatorID
		--	, CASE	WHEN indicatorID='01' THEN 1
		--			WHEN indicatorID='11' AND MAX([Value]) >2 THEN 2 
		--			ELSE MAX([Value])
		--	END as 'Y-Axis_Max'
		--	, CASE	WHEN indicatorID in ('01','11','12','13','16','18','40') THEN 0
		--			ELSE MIN([Value])
		--	END as 'Y-Axis_Min'	
		--	, CASE	WHEN MAX(LEFT([FORMAT],1))='P' THEN CAST(MAX(RIGHT([FORMAT],1)) as int) +2
		--			ELSE CAST(MAX(RIGHT([FORMAT],1)) as int)
		--	END as 'RoundPrecision'
		--	FROM DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS]
		--	WHERE indicatorID !='04'
		--	AND [Value] is not null
		--	AND Hide_Chart =0
		--	GROUP BY IndicatorID
		--) as Y
		--ON X.IndicatorID=Y.IndicatorID
		--LEFT JOIN (
		--	SELECT distinct indicatorID
		--	, Program
		--	, MAX([Value]) as 'Y-Axis_Max'
		--	, MIN([Value]) as 'Y-Axis_Min'	
		--	, CASE	WHEN MAX(LEFT([FORMAT],1))='P' THEN CAST(MAX(RIGHT([FORMAT],1)) as int) +2
		--			ELSE CAST(MAX(RIGHT([FORMAT],1)) as int)
		--	END as 'RoundPrecision'
		--	FROM DSSI.[dbo].[TRUE_NORTH_RICHMOND_INDICATORS]
		--	WHERE indicatorID ='04'
		--	GROUP BY IndicatorID, Program
		--) as Z
		--ON X.IndicatorID=Z.IndicatorID AND X.Program=Z.Program
		--WHERE 1 =  X.Scorecard_eligible
		--;
		--ORDER BY IndicatorID ASC, Program ASC, TimeFrameUnit ASC 

------------
-- END QUERY
------------
