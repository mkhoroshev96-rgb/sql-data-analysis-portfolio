-- 788. «Індекс фантомної стабільності постачальника»

WITH level1 as(SELECT supplier_id
       ,order_id
	   ,order_date
	   ,(p.unit_price * quantity * (1-discount)) as chek
	   ,COUNT(*) OVER (partition by supplier_id) as count_position
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN suppliers USING (supplier_id)),
level2 as(SELECT *   
FROm level1
WHERE count_position >= 120),
level3 as(SELECT supplier_id
       ,AVG(chek) as avg_chek
	   ,percentile_cont (0.5) WITHIN GROUP (order by chek) as median_chek
FROm level2
GROUP BY supplier_id)
SELECT *
       ,avg_chek / median_chek as fsi
FROm level3
ORDER BY fsi DESC

-- 789. «ARPU по країнах»

WITH level1 as(SELECT ship_country
       ,customer_id
       ,(unit_price * quantity * (1-discount)) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN customers USING (customer_id)),
level2 as(SELECT ship_country
       ,SUM(chek) as sum_chek
	   ,COUNT(DISTINCT customer_id) as count_customer
FROM level1
GROUP bY ship_country)
SELECT *
       ,sum_chek / count_customer as apru
FROm level2
WHERE count_customer >= 5
ORDER BY apru DESC

-- 790. «Країна одного клієнта»

WITH level1 as(SELECT ship_country
       ,order_id
	   ,customer_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN customers USING (customer_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by ship_country, customer_id) as revenue_customer_in_country
	   ,SUM(chek) OVER (partition by ship_country) as revenue_country
FROm level1),
level3 as(SELECT DISTINCT ship_country
       ,customer_id
	   ,revenue_customer_in_country
	   ,revenue_country
	   ,MAX(revenue_customer_in_country) OVER (partition by ship_country) as max_revenue_customer
FROm level2),
level4 as(SELECT *
       ,max_revenue_customer / revenue_country as ratio
FROM level3
WHERE revenue_customer_in_country = max_revenue_customer)
SELECT *
FROM level4
WHERE ratio > 0.5

-- 791. «Індекс фальшивого ARPU»

WITH level1 as(SELECT ship_country
       ,customer_id
       ,order_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN customers USING (customer_id)),
level2 as(SELECT ship_country
       ,SUM(chek) as sum_chek
	   ,COUNT(DISTINCT customer_id) as count_customer
FROm level1
GROUP BY ship_country),
level3 as(SELECT *
       ,SUM(chek) OVER (partition by ship_country, customer_id) as customer_revenue
	   ,sum_chek / count_customer as apru
FROM level1
JOIN level2 USING (ship_country)),
level4 as(SELECT DISTINCT ship_country
       ,customer_id
	   ,sum_chek
	   ,count_customer
	   ,customer_revenue
	   ,apru
FROm level3
ORDER BY ship_country),
level5 as(SELECT ship_country
       ,percentile_cont(0.5) WITHIN GROUP (order by customer_revenue) as median_customer_revenue
FROM level4
GROUP By ship_country),
level6 as(SELECT distinct ship_country
       ,apru / median_customer_revenue as far
FROM level4
JOIN level5 USING (ship_country))
SELECT *
FROM level6
WHERE far > 1
ORDER BY far DESC

-- 792. «Центр гравітації доходу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,corr(sum_chek, rn) as corr_chek_rn
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when corr_chek_rn > 0 THEN 'progress'
	   when corr_chek_rn < 0 THEN 'degradation'
	   END as classification
FROm level2)
SELECT *
FROM level3
WHERE corr_chek_rn is not null
ORDER BY corr_chek_rn DESC

-- 793. «Клієнт із інерційною пам'яттю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek 
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,corr(sum_chek, prev_chek) as imi
FROm level2
GROUP BY customer_id)
SELECT *
       ,case when imi > 0.8 THEN 'inertion_cheks'
	   when imi between 0 AND 0.2 THEN 'random_bay'
	   when imi < 0 THEN 'compensation_bay'
	   else 'alles_ist_ok' END as gradation
FROm level3
ORDER BY imi DESC

-- 794. «Клієнт із дзеркальним чеком»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date, order_id) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 12),
level3 as(SELECT a.customer_id
        ,a.sum_chek as chek_a
		,b.sum_chek as chek_b
FROm level2 a
JOIN level2 b ON a.customer_id = b.customer_id
AND a.rn = abs(b.rn - b.count_order) + 1)
SELECT customer_id
       ,corr(chek_a, chek_b) as corr_a_and_b
FROm level3
GROUP By customer_id
ORDER BY corr_a_and_b DESC

-- 795. «Клієнт із фантомною стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
	   ,STDDEV(sum_chek) OVER (partition by customer_id) as stddev_chek
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,stddev_chek
FROm level2),
level4 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by avg_chek) FROM level3) as global_median
FROm level3),
level5 as(SELECT *
       ,stddev_chek / avg_chek as cv
FROm level4
WHERE avg_chek > global_median AND count_order >= 10)
SELECT *
FROm level5
WHERE cv > 1

-- 796. «Клієнт із зламаним центром ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,sum_chek * rn as chek_and_rn
	   ,(count_order + 1) / 2 as central_rn
	   ,count_order * 0.25 as count_25_perc
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,central_rn
	   ,count_25_perc
       ,SUM(chek_and_rn) / SUM(sum_chek) as cog
FROm level2
GROUP By customer_id, central_rn, count_25_perc),
level4 as(SELECT *
       ,cog - central_rn as shift
FROm level3)
SELECT *
FROm level4
WHERE shift > count_25_perc

-- 797. «Клієнт із розірваною історією покупок»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ABS(sum_chek - prev_chek) as diff 
FROm level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,AVG(diff) OVER (partition by customer_id) as avg_diff
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,avg_diff
       ,avg_diff / avg_chek as rupture_index 
FROm level4)
SELECT *
FROm level5
WHERE rupture_index  > 0.8