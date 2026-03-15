-- 235. “Клієнти з нерівномірними покупками в часі”

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
       ,order_id
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date 
       ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROm level2
WHERE count_order >= 5),
level4 as(SELECT customer_id
       ,MAX(interval) as max_interval
	   ,MIN(interval) as min_interval
FROM level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE max_interval >= 20 AND min_interval <= 3

-- 236. “Клієнти з нерівномірними паузами, але стабільною активністю”

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
       ,order_id
FROM orders),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROm level2
WHERE count_order >= 6 AND prev_date is not null),
level4 as(SELECT customer_id
       ,MAX(interval) as max_interval
	   ,MIN(interval) as min_interval
	   ,ROUND(AVG(interval)::numeric,2) as avg_interval
	   ,percentile_cont(0.5) within group (order by interval) as median_interval
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND(ABS(avg_interval - median_interval)::numeric,2) as abs_diff_interval
FROM level4)
SELECT *
FROM level5
WHERE max_interval >= 20 AND min_interval <=3 AND abs_diff_interval <= 2

-- 237. “Клієнти з нестабільною вартістю одиниці товару”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price_after_discount
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(AVG(avg_price_after_discount)::numeric,2) as avg_price_per_customer
	   ,MAX(avg_price_after_discount) as max_price
	   ,MIN(avg_price_after_discount) as min_price
FROM level1
WHERE count_order >= 5
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND((max_price::numeric / avg_price_per_customer::numeric),2) as max_ratio
	   ,ROUND((min_price::numeric / avg_price_per_customer::numeric),2) as min_ratio
FROm level2)
SELECt *
FROm level3
WHERE max_ratio >= 1.3 AND min_ratio <= 0.7

-- 238. “Працівники з нестабільною логістикою”

WITH level1 as(SELECT DISTINCT order_date
       ,shipped_date
       ,employee_id
	   ,ship_country
FROM orders
JOIN order_details USING (order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
JOIN employees USING(employee_id)),
level2 as(SELECT employee_id
       ,order_date
	   ,shipped_date
	   ,ship_country
	   ,COUNT(*) OVER (partition by employee_id) as count_order
FROM level1),
level3 as(SELECT employee_id
       ,COUNT(DISTINCT ship_country) as count_ship_country
FROM orders
JOIN order_details USING (order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
JOIN employees USING(employee_id)
GROUP BY employee_id),
level4 as(SELECT *
FROM level2
JOIN level3 USING (employee_id)),
level5 as(SELECT employee_id
       ,ship_country
	   ,ROUND(AVG(shipped_date - order_date)::numeric,2) as avg_interval
FROM level4
WHERE count_order >= 20 AND count_ship_country >= 4
GROUP BY employee_id, ship_country),
level6 as(SELECT employee_id
       ,MAX(avg_interval) as max_avg_interval
	   ,MIN(avg_interval) as min_avg_interval
FROM level5
GROUP BY employee_id),
level7 as(SELECT *
       ,max_avg_interval - min_avg_interval as diff
FROm level6)
SELECT *
FROM level7 
WHERE diff >= 5

-- 239. “Постачальники з ефектом залежності від одного працівника”

WITH level1 as(SELECT DISTINCT order_date
       ,supplier_id
	   ,employee_id
FROM orders
JOIn order_details USING(order_id)
JOIn products USING(product_id)
JOIN categories USING(category_id)
JOIN employees USING(employee_id)),
level2 as(SELECT supplier_id
       ,order_date
	   ,employee_id
FROM level1
ORDER BY supplier_id, order_date),
level3 as(SELECT supplier_id
       ,COUNT(DISTINCT employee_id) as count_dist_empl
FROM orders
JOIn order_details USING(order_id)
JOIn products USING(product_id)
JOIN categories USING(category_id)
JOIN employees USING(employee_id)
GROUP BY supplier_id),
level4 as(SELECT *
FROM level2
JOIn level3 USING(supplier_id)),
level5 as(SELECT *
       ,COUNT(*) OVER (partition by supplier_id,employee_id) as count_order_empl
	   ,COUNT(*) OVER (partition by supplier_id) as total_count
FROM level4
WHERE count_dist_empl >= 3),
level6 as(SELECT DISTINCT supplier_id,employee_id
	   ,ROUND(((count_order_empl::numeric /  total_count::numeric)*100),2) as ratio
FROM level5),
level7 as(SELECT *
       ,ROW_NUMBER() OVER (partition by supplier_id order by ratio DESC) as rn_ratio
FROm level6)
SELECT *
FROm level7
WHERE rn_ratio = 1 AND ratio >= 50

-- 240. “Працівники з вузькою клієнтською спеціалізацією”

WITH level1 as(SELECT DISTINCT order_date
       ,employee_id
       ,c.country
	   ,COUNT(*) OVER (partition by employee_id, c.country) as count_country_empl
	   ,COUNT(*) OVER (partition by employee_id) as total_count
FROM orders
JOIN order_details USING (order_id)
JOIN products USING (product_id)
JOIN customers c USING(customer_id)
JOIN employees USING(employee_id)
ORDER BY employee_id),
level2 as(SELECT DISTINCT employee_id,country
       ,ROUND(((count_country_empl::numeric / total_count::numeric)*100),2) as ratio
FROM level1),
level3 as(SELECT *
       ,ROW_NUMBER() OVER (partition by employee_id order by ratio DESC) as rn_ratio
FROm level2)
SELECT *
FROM level3
WHERE rn_ratio = 1 AND ratio >= 60

-- 241. “Клієнти з ефектом зламаного чеку”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id,order_id,order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP BY customer_id),
level4 as(SELECT *
FROM level2
JOIn level3 USING(customer_id)),
level5 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_sum_per_customer
FROM level4),
level6 as(SELECT *
       ,ROUND(((sum_chek/total_sum_per_customer)*100),2) as ratio
FROM level5),
level7 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by ratio DESC) as rn_ratio
FROM level6)
SELECT *
FROm level7
WHERE avg_chek >= median_chek * 1.5 AND rn_ratio = 1 AND ratio >= 35