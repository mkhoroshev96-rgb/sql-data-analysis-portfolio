-- 345. «Дорога дрібнота»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ship_country
       ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(freight)::numeric,2) as avg_freight
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, ship_country,order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER ()::numeric,2) as avg_quantity
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_chek) FROM level1) as median_chek
	   ,ROUND((SELECT percentile_cont(0.5) WITHIN GROUP (order by avg_freight) FROM level1)::numeric,2) as median_freight
FROM level1),
level3 as(SELECT *
       ,COUNT(order_id) OVER (partition by ship_country) as count_order
FROM level2
WHERE sum_quantity < avg_quantity AND avg_freight > median_freight AND sum_chek >= median_chek)
SELECT *
FROM level3
WHERE count_order >= 3

-- 346. «Стабільні клієнти з хаотичним чеком»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
       ,ROUND(STDDEV(sum_quantity) OVER (partition by customer_id)::numeric,2) as std_dev_quantity
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((std_dev_quantity / avg_quantity)::numeric,2) as cv_quantity
	   ,ROUND((std_dev_chek / avg_chek)::numeric,2) as cv_chek
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,max_chek
	   ,ROUND((max_chek / avg_chek)::numeric,2) as ratio_max
	   ,min_chek
	   ,ROUND((min_chek / avg_chek)::numeric,2) as ratio_min
	   ,std_dev_quantity
	   ,avg_quantity
	   ,std_dev_chek
	   ,avg_chek
	   ,cv_quantity
	   ,ROUND(AVG(cv_quantity) OVER ()::numeric,2) as avg_cv_quantity
	   ,cv_chek
	   ,ROUND(AVG(cv_chek) OVER ()::numeric,2) avg_cv_chek
FROM level3)
SELECT *
FROM level4
WHERE cv_quantity < avg_cv_quantity AND cv_chek > avg_cv_chek
AND ratio_min < 0.6 AND ratio_max > 1.6

-- 347. «Клієнти з фальшивим зростанням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level2
GROUP By customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id, halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as median_chek_first
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as median_chek_second
FROm level4
GROUP By customer_id),
level6 as(SELECt *
       ,case when sum_chek > median_chek_second * 1.5 THEN 1 ELSE 0 END as flag_chek
FROm level4
JOIN level5 USING(customer_id)
WHERE avg_chek_second > avg_chek_first AND median_chek_second <= median_chek_first),
level7 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level6)
SELECT *
FROm level7
WHERE sum_flag_chek <= 2

-- 348. «Клієнти з ефектом стискання»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level2
GROUP By customer_id, halfs),
level4 as(SELECT *
FROm level2
JOIn level3 USING (customer_id, halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as median_chek_first
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as median_chek_second
FROm level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
FROM level4
JOIn level5 USING (customer_id)),
level7 as(SELECT *
FROm level6
WHERE median_chek_second >= median_chek_first AND diff_chek <= 0.1),
level8 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.25) WITHIN GROUP (order by sum_chek) as first_percentile
	   ,percentile_cont(0.75) WITHIN GROUP (order by sum_chek) as third_percentile
FROm level7
GROUP By customer_id, halfs),
level9 as(SELECT *
FROM level7
JOIn level8 USING (customer_id, halfs)),
level10 as(SELECT customer_id
       ,ROUND(AVG(first_percentile) FILTER (WHERE halfs = 'first_half')::numeric,2) as first_percentile_first
	   ,ROUND(AVG(third_percentile) FILTER (WHERE halfs = 'first_half')::numeric,2) as third_percentile_first
	   ,ROUND(AVG(first_percentile) FILTER (WHERE halfs = 'second_half')::numeric,2) as first_percentile_second
	   ,ROUND(AVG(third_percentile) FILTER (WHERE halfs = 'second_half')::numeric,2) as third_percentile_second
FROM level9
GROUP By customer_id),
level11 as(SELECT *
       ,third_percentile_first - first_percentile_first as diff_IQR_first
	   ,third_percentile_second - first_percentile_second as diff_IQR_second
FROM level9
JOIn level10 USING (customer_id))
SELECT *
FROm level11
WHERE diff_IQR_second <= diff_IQR_first * 0.6

-- 349. «Стиснення без зміни медіани — але по товарах»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id) as rn
FROM orders
JOIn order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROm level2
JOIn level3 USING (customer_id, halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(median_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as median_quantity_first
	   ,ROUND(AVG(median_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as median_quantity_second
FROM level4
GROUP By customer_id),
level6 as(SELECT *
       ,ROUND(ABS((avg_quantity_second - avg_quantity_first) / avg_quantity_first)::numeric,2) as diff_quantity
FROM level4
JOIN level5 USING (customer_id)),
level7 as(SELECT *
FROm level6
WHERE diff_quantity <= 0.15 AND median_quantity_second >= median_quantity_first),
level8 as(SELECT customer_id
       ,halfs
       ,percentile_cont(0.25) WITHIN GROUP (order by sum_quantity) as first_percentile
	   ,percentile_cont(0.75) WITHIN GROUP (order by sum_quantity) as third_percentile
FROm level7
GROUP By customer_id, halfs),
level9 as(SELECT *
FROM level7
JOIn level8 USING (customer_id, halfs)),
level10 as(SELECT customer_id
       ,ROUND(AVG(first_percentile) FILTER (WHERE halfs = 'first_half')::numeric,2) as first_percentile_first
	   ,ROUND(AVG(third_percentile) FILTER (WHERE halfs = 'first_half')::numeric,2) as third_percentile_first
	   ,ROUND(AVG(first_percentile) FILTER (WHERE halfs = 'second_half')::numeric,2) as first_percentile_second
	   ,ROUND(AVG(third_percentile) FILTER (WHERE halfs = 'second_half')::numeric,2) as third_percentile_second
FROM level9
GROUP By customer_id),
level11 as(SELECT *
       ,third_percentile_first - first_percentile_first as IQR_first
	   ,third_percentile_second - first_percentile_second as IQR_second
FROM level9
JOIn level10 USING (customer_id))
SELECT *
FROm level11
WHERE IQR_second / IQR_first <= 0.5