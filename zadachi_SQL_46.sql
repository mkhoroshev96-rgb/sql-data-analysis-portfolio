-- 291. “Клієнти з ефектом першого великого замовлення”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn = 1 THEN 'first_order' 
	   ELSE 'other_orders' END as flag_order
FROM level1
WHERE count_order >= 3),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE flag_order = 'first_order')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_order = 'other_orders')::numeric,2) as avg_chek_other
FROM level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_chek_first > avg_chek_other

-- 292. “Клієнти з ілюзією зростання”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND((SUM(unit_price * (1-discount))/SUM(quantity))::numeric,2) as avg_price_per_unit
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LAG(avg_price_per_unit) OVER (partition by customer_id order by order_date) as prev_avg_price
FROm level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 1 ELSE 0 END as flag_chek
	   ,case when avg_price_per_unit < prev_avg_price THEN 1 ELSE 0 END as flag_price
	   ,count_order - 1 as real_count_order
FROM level2
WHERE prev_chek is not null AND prev_avg_price is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
	   ,SUM(flag_price) OVER (partition by customer_id) as sum_flag_price
FROM level3)
SELECT *
FROM level4
WHERE real_count_order = sum_flag_chek AND real_count_order = sum_flag_price

-- 293. “Клієнти з ефектом компенсації”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as total_avg_chek
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by total_avg_chek) FROM level2) as median
       ,case when sum_chek > prev_chek THEN 1 ELSE 0 END as flag_chek
	   ,count_order - 1 as real_count_order
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) sum_flag_chek
FROM level3)
SELECT *
FROM level4
WHERE sum_flag_chek <> real_count_order AND total_avg_chek > median

-- 294. “Клієнти з ефектом роздутої стабільності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek)::numeric,2) as std_dev_chek
	   ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity
	   ,ROUND(STDDEV(sum_quantity)::numeric,2) as std_dev_quantity
FROM level1
WHERE count_order >= 6
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND((std_dev_chek / avg_chek)::numeric,2)  as flag_ratio_chek
	   ,ROUND((std_dev_quantity / avg_quantity)::numeric,2) as flag_ratio_quantity
FROM level2)
SELECT *
FROM level3
WHERE flag_ratio_chek < 0.25 AND flag_ratio_quantity > 0.5

-- 295. “Клієнти з асиметрією кошика”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND(AVG(avg_chek) OVER ()::numeric,2) as total_avg_chek
FROM level2),
level4 as(SELECT customer_id
       ,order_id
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
GROUP By customer_id, order_id),
level5 as(SELECT l3.*
       ,l4.count_order
FROM level3 l3
JOIN level4 l4 USING(customer_id))
SELECT DISTINCT customer_id, avg_quantity,median_quantity,avg_chek,total_avg_chek,count_order
FROM level5
WHERE median_quantity < 0.7 * avg_quantity AND avg_chek > total_avg_chek

