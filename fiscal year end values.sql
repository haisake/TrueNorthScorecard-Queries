/*
Purpose: To pull Fiscal year indicator values for the fiscal year end slide.
Author: Hans Aisake
Date Created: April 14, 2020
Comments:
There are many indicators that can't be pulled this way. Nor am I currently sure if this is the right source to be useing.
Most of these indicators are old BSC indicators that perhaps should be pulled from another source.

-- Adimtted within 10 hrs 1, ALC rate 7,   ALOS of LLOS 31, 28 day readmissions
*/

------------------------
-- Rate indicators
------------------------
	-- current fiscal year
	SELECT IndicatorID
	, IndicatorName 
	, '2019/20' as 'TimeFrame'
	, SUM(Numerator) as 'Numerator'
	, SUM(Denominator) as 'Denominator'
	, 1.0*SUM(Numerator)/SUM(Denominator) as 'VALUE'
	, AVG([Target]) as 'Target'			--might not be right
	, COUNT(numerator)
	FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS
	WHERE (
	Program='Overall'
	OR (Program='Home & Community Care' AND indicatorID in(23,24,27,29))
	)
	AND TimeFrame BETWEEN '2019-04-01' AND '2020-03-31'	--CURRENT FISCAL YEAR
	AND Denominator is not null	--indicators with denominators
	--AND IndicatorID in (1,7, 31, 33) 
	AND Facility like '%Richmond%'
	GROUP BY  IndicatorID
	, IndicatorName
	--HAVING COUNT(Numerator)=13
	ORDER BY IndicatorID ASC

	-- last fiscal year
	SELECT IndicatorID
	, IndicatorName 
	, '2018/19' as 'TimeFrame'
	, SUM(Numerator) as 'Numerator'
	, SUM(Denominator) as 'Denominator'
	, 1.0*SUM(Numerator)/SUM(Denominator) as 'VALUE'
	, AVG([Target]) as 'Target'			--might not be right
	, COUNT(numerator)
	FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS
	WHERE (
	Program='Overall'
	OR (Program='Home & Community Care' AND indicatorID in(23,24,27,29))
	)
	AND TimeFrame BETWEEN '2018-04-01' AND '2019-03-31'	--CURRENT FISCAL YEAR
	AND Denominator is not null	--indicators with denominators
	--AND IndicatorID in (1,7, 31, 33) 
	AND Facility like '%Richmond%'
	GROUP BY  IndicatorID
	, IndicatorName
	HAVING COUNT(Numerator)=13
	ORDER BY IndicatorID ASC

------------------------
-- Raw value indictors
------------------------
	-- current fiscal year
	SELECT IndicatorID
	, IndicatorName 
	, '2019/20' as 'TimeFrame'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, AVG([Value]) as 'VALUE'			--I disagree with this but it's how the BSC works
	, AVG([Target]) as 'Target'			--might not be right
	, COUNT([Value])
	FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS
	WHERE  (
	Program='Overall'	AND indicatorID in ('05')
	OR Program='Home & Community Care' AND IndicatorID in ('29')
	)
	AND TimeFrame BETWEEN '2019-04-01' AND '2020-03-31'	--CURRENT FISCAL YEAR
	--AND IndicatorID in (1,7, 31, 33) 
	AND Facility like '%Richmond%'
	GROUP BY  IndicatorID
	, IndicatorName
	--HAVING COUNT([Value])=13
	ORDER BY IndicatorID ASC

	-- last fiscal year
	SELECT IndicatorID
	, IndicatorName 
	, '2018/19' as 'TimeFrame'
	, NULL as 'Numerator'
	, NULL as 'Denominator'
	, AVG([Value]) as 'VALUE'			--I disagree with this but it's how the BSC works
	, AVG([Target]) as 'Target'			--might not be right
	, COUNT([Value])
	FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS
	WHERE (
	Program='Overall'	AND indicatorID in ('05')
	OR Program='Home & Community Care' AND IndicatorID in ('29')
	)
	AND TimeFrame BETWEEN '2018-04-01' AND '2019-03-31'	--CURRENT FISCAL YEAR
	--AND IndicatorID in (1,7, 31, 33) 
	AND Facility like '%Richmond%'
	GROUP BY  IndicatorID
	, IndicatorName
	--HAVING COUNT([Value])=13
	ORDER BY IndicatorID ASC

SELECT distinct indicatorId, indicatorName, program FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS

SELECT * FROM DSSI.dbo.TRUE_NORTH_RICHMOND_INDICATORS WHERE indicatorID='29'




