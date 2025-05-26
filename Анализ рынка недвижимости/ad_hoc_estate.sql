/*
 * Анализ рынка недвижимости Санкт-Петербурга и Ленинградской области
 * 
 * Основные задачи:
 * 1. Анализ активности объявлений
 * 2. Исследование сезнности объявлений
 * 3. Анализ рынка недвижимости
 * 
 * Автор: Клементьев В.Д.
 * Дата: 02.02.25
 * Версия SQL: PostgreSQL 13+
*/
--1. Время активности объявлений
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
categories AS (
SELECT
	*,
	CASE
		WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
		ELSE 'ЛенОбл'
	END AS region,
	CASE
		WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'месяц'
		WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'квартал'
		WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'квартал'
		WHEN a.days_exposition > 180 AND a.days_exposition IS NOT NULL THEN 'больше полугода'
		ELSE 'не снято'
	END AS activity,
	ROUND((a.last_price / f.total_area)::numeric, 2) AS price_per_sqrm
FROM real_estate.flats f
INNER JOIN real_estate.city c USING(city_id)
INNER JOIN real_estate.advertisement a USING(id)
INNER JOIN real_estate.type t USING(type_id)
WHERE id IN (SELECT * FROM filtered_id) AND t.type = 'город'
)

SELECT 
	region,
	activity,
	ROUND(AVG(price_per_sqrm), 2) AS avg_price_per_sqrm,
	ROUND(AVG(total_area)::numeric, 2) AS avg_area,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony,
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS median_floor
FROM categories
GROUP BY region, activity;

--2. Сезонность объявлений
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit
    FROM real_estate.flats
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    INNER JOIN real_estate.type USING(type_id)
    WHERE total_area < (SELECT total_area_limit FROM limits)
      AND type = 'город'
),
publish_activity AS (
    SELECT 
        TO_CHAR(first_day_exposition, 'Month') AS month,
        COUNT(id) AS publish_count,
        ROUND(AVG(total_area)::numeric, 2) AS avg_publish_area,
        ROUND(AVG(last_price / total_area)::numeric, 2) AS avg_publish_price_per_sqm
    FROM real_estate.advertisement
    INNER JOIN real_estate.flats USING(id)
    WHERE id IN (SELECT * FROM filtered_id)
      AND EXTRACT(YEAR FROM first_day_exposition) NOT IN (2014, 2019)
    GROUP BY TO_CHAR(first_day_exposition, 'Month')
),
remove_activity AS (
    SELECT
      TO_CHAR(first_day_exposition + INTERVAL '1 day' * days_exposition, 'Month') AS month,
      COUNT(id) AS remove_count,
      ROUND(AVG(total_area)::numeric, 2) AS avg_remove_area,
      ROUND(AVG(last_price / total_area)::numeric, 2) AS avg_remove_price_per_sqm
    FROM real_estate.advertisement
    INNER JOIN real_estate.flats USING(id)
    WHERE id IN (SELECT * FROM filtered_id)
      AND EXTRACT(YEAR FROM first_day_exposition + INTERVAL '1 day' * days_exposition) NOT IN (2014, 2019)
      AND days_exposition IS NOT NULL 
    GROUP BY TO_CHAR(first_day_exposition + INTERVAL '1 day' * days_exposition, 'Month')
)
SELECT
    COALESCE(p.month, r.month) AS month,
    p.publish_count,
    r.remove_count,
    p.avg_publish_area,
    r.avg_remove_area,
    p.avg_publish_price_per_sqm,
    r.avg_remove_price_per_sqm
FROM publish_activity p
FULL JOIN remove_activity r ON p.month = r.month
ORDER BY p.publish_count DESC, r.remove_count DESC;

--3. Анализ рынка недвижимости Ленобласти
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit
    FROM real_estate.flats
),
filtered_id AS(
SELECT id
FROM real_estate.flats  
WHERE total_area < (SELECT total_area_limit FROM limits)
),
publish_activity AS (
SELECT 
	c.city,
	COUNT(f.id) AS publish_count,
	AVG(COUNT(f.id)) OVER() AS avg_publish,
	ROUND(COUNT(a.days_exposition)::numeric / COUNT(f.id), 2) AS remove_share,
	ROUND(AVG(total_area)::numeric, 2) AS avg_area,
	ROUND((SUM(a.last_price) / SUM(total_area))::numeric, 2) AS avg_price_per_sqrm,
	ROUND(AVG(days_exposition)::numeric, 2) AS avg_days_exposition
FROM real_estate.flats f
INNER JOIN real_estate.city c USING(city_id)
INNER JOIN real_estate.advertisement a USING(id)
WHERE city != 'Санкт-Петербург' AND id IN (SELECT * FROM filtered_id)
GROUP BY c.city
)

SELECT 
	city,
	publish_count,
	remove_share,
	avg_area,
	avg_price_per_sqrm
FROM publish_activity
WHERE publish_count > avg_publish
ORDER BY publish_count DESC, remove_share DESC
LIMIT 15;
