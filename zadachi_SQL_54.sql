-- 341. “Активні, але маловартісні клієнти з ілюзією дороговизни”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,count_order
	   ,total_revenue
	   ,avg_chek
FROM level2),
level4 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by count_order DESC) as rank_count
	   ,NTILE(4) OVER (order by count_order DESC) as ntile_count
FROm level3),
level5 as(SELECT customer_id
       ,DENSE_RANK() OVER (order by total_revenue DESC) as rank_revenue
	   ,NTILE(4) OVER (order by total_revenue DESC) as ntile_revenue
FROM level3),
level6 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by avg_chek desc) as rank_avg_chek
	   ,NTILE(5) OVER (order by avg_chek desc) as ntile_avg_chek
FROM level3)
SELECT *
FROM level3
JOIN level4 USING (customer_id)
JOIN level5 USING (customer_id)
JOIN level6 USING (customer_id)
WHERE ntile_count = 1 AND ntile_revenue = 4 AND ntile_avg_chek IN (1,2)

-- 342. «Клієнти з ілюзією стабільності»

WITH block_1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount)) OVER (partition by customer_id, order_id)::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT DISTINCT customer_id, order_id, order_date, sum_chek
FROm level1),
level3 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
       ,DENSE_RANK () OVER (partition by customer_id order by sum_chek DESC) as rank_chek
	   ,NTILE(4) OVER (partition by customer_id order by sum_chek DESC) as ntile_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level2),
level4 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id, ntile_chek) as revenue_per_ntile
FROm level3
WHERE count_order >= 4),
level5 as(SELECT *
       ,ROUND(((revenue_per_ntile::numeric / total_revenue::numeric) *100),2) as ratio
FROM level4)
SELECT customer_id
       ,ntile_chek
	   ,revenue_per_ntile
	   ,total_revenue
	   ,ratio
FROM level5),
block_2 as(WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::Numeric,2) as avg_chek
FROm level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,ROUND(AVG(interval) OVER (partition by customer_id)::numeric,2) as avg_interval
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,interval
	   ,avg_chek
FROM level3),
level5 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by interval DESC) as rank_interval
	   ,ntile(5) OVER (order by interval DESC) as ntile_interval
FROM level4),
level6 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by avg_chek DESC) as rank_avg_chek
	   ,NTILE(5) OVER (order by avg_chek DESC) as ntile_avg_chek
FROM level4)
SELECT DISTINCT customer_id
       ,ntile_interval
	   ,ntile_avg_chek
FROM level4
JOIN level5 USING(customer_id)
JOIN level6 USING(customer_id))
SELECT *
FROM block_1
JOIn block_2 USING(customer_id)
WHERE (ntile_chek = 1 AND ratio >= 70) AND ntile_interval = 3 AND ntile_avg_chek = 3

-- 343. «Замовлення-парадокс клієнта»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id
ORDER BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when sum_chek < avg_chek AND sum_chek > median_chek THEN 'yes' ELSE 'no' END as flag
FROM level1
JOIn level2 USING(customer_id))
SELECT *
FROM level3
WHERE flag = 'yes'

-- 344. «Клієнти з локальною ілюзією стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,case when rn_invert <= 3 THEN 'last_3'
	   ELSE 'other' END as gradation
FROm level2),
level4 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id, gradation) as max_chek_in_last
	   ,MIN(sum_chek) OVER (partition by customer_id, gradation) as min_chek_in_last
FROM level3
WHERE gradation = 'last_3'),
level5 as(SELECT *
       ,ROUND((max_chek/min_chek)::numeric,2) as diff_chek
	   ,ROUND((max_chek_in_last / min_chek_in_last)::numeric,2) as diff_chek_last 
FROm level4)
SELECT *
FROM level5
WHERE diff_chek >= 3 AND diff_chek_last <= 1.1