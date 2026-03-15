-- 389. “Клієнти з нестабільним чеком”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECt *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,case when sum_chek > avg_chek AND sum_chek < global_avg_chek THEN 'yes' 
	   ELSE 'no' END as gradation
FROM level2)
SELECT *
FROm level3
WHERE gradation = 'yes'

-- 390. “Клієнти з ефектом роздутого замовлення”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,case when sum_quantity > avg_quantity AND sum_chek < avg_chek THEN 1 ELSE 0 END as flag_chek_quantity
FROM level2),
level4 as(SELECT *
       ,SUM(flag_chek_quantity) OVER (partition by customer_id) as sum_flag
FROM level3)
SELECT *
FROM level4
WHERE sum_flag = 1 

-- 391. «Клієнти з фальшивою стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(((max_chek - min_chek) / avg_chek)::numeric,2) as diff_chek
	   ,ROUND(ABS((sum_quantity - avg_quantity) / avg_quantity)::numeric,2) as diff_quantity 
FROM level2)
SELECT *
FROm level3
WHERE diff_chek < 0.25 AND diff_quantity > 0.5

-- 392. «Клієнти з локальним перекосом структури»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
	   ,SUM(quantity) OVER (partition by customer_id,order_id) as total_quantity_order
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROUND(((quantity::numeric / total_quantity_order::numeric) * 100)::numeric,2) as diff_quantity
FROM level1),
level3 as(SELECT *
       ,ROUND(AVG(diff_quantity) OVER (partition by customer_id)::numeric,2) as global_avg_diff_quantity
FROM level2),
level4 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id)
SELECT *
FROM level3
JOIN level4 USING (customer_id)
WHERE count_order >= 5 AND diff_quantity >global_avg_diff_quantity

-- 393. «Клієнти з різким зсувом структури»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
	   ,SUM(quantity) OVER (partition by customer_id,order_id) as total_quantity_order
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROUND(((quantity::numeric / total_quantity_order::numeric)*100)::numeric,2) as diff_quantity
FROM level1),
level3 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id, order_id order by diff_quantity DESC) as ranks
FROM level2),
level4 as(SELECT customer_id
       ,count(order_id) as count_order
	   ,COUNT(order_id) / 2 as middle_point
FROM orders
GROUP By customer_id),
level5 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by order_date) as rn
FROM level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level5
WHERE ranks = 1 AND count_order >= 6),
level7 as(SELECT customer_id
       ,ROUND(AVG(diff_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_diff_quantity_first
	   ,ROUND(AVG(diff_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_diff_quantity_second
FROm level6
GROUP By customer_id),
level8 as(SELECT *
       ,ROUND((avg_diff_quantity_second / avg_diff_quantity_first)::numeric,2) as ratio
FROm level7)
SELECT *
FROM level8
WHERE ratio >= 2

-- 394. «Клієнти з ілюзією вигідності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,sum(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,ROUND((SUM(sum_chek) / SUM(sum_quantity))::numeric,2) as avg_price_per_customer
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(AVG(avg_price_per_customer) OVER ()::numeric,2) as global_avg_price
FROM level2
JOIN level3 USING (customer_id))
SELECT *
FROM level4
WHERE avg_chek_customer > global_avg_chek AND avg_price_per_customer < global_avg_price 

-- 395. «Клієнти з ефектом компенсації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
	   ,quantity
FROm orders
JOIn order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,ROUND((SUM(chek) / sum(quantity))::numeric,2) as avg_price_per_order
FROM level1
GROUP By customer_id, order_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT customer_id
       ,ROUND((sum(chek) / sum(quantity))::numeric,2) as avg_price_per_customer
FROM level3
GROUP By customer_id),
level5 as(SELECT *
       ,case when avg_price_per_order > avg_price_per_customer THEN 'high'
	   when avg_price_per_order < avg_price_per_customer THEN 'low'
	   END as categories
FROm level3
JOIN level4 USING (customer_id)),
level6 as(SELECT customer_id
       ,ROUND(avg(quantity) FILTER (WHERE categories = 'high')::numeric,2) as avg_quantity_high
	   ,ROUND(AVG(quantity) FILTER (WHERE categories = 'low')::numeric,2) as avg_quantity_low
FROM level5
GROUP By customer_id)
SELECT *
FROm level6
WHERE avg_quantity_low > avg_quantity_high

-- 396. «Клієнти з хибним зростанням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2)::numeric,2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as avg_price_per_order
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half' 
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (where halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (where halfs = 'second_half')::numeric,2) as avg_chek_second
	   ,ROUND(sum(sum_chek) / sum(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_price_first
	   ,ROUND(sum(sum_chek) / sum(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_price_second
FROM level3
GROUP BY customer_id)
SELECT *
FROm level4
WHERE avg_chek_second > avg_chek_first AND avg_price_second <= avg_price_first

-- 397. «Клієнти з фальшивою частотою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition  by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2)::numeric,2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level2 as(SELECT *
       ,order_date - prev_date as interval
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE halfs = 'first')::numeric,2) as avg_interval_first
	   ,ROUND(AVG(interval) FILTER (WHERE halfs = 'second')::numeric,2) as avg_interval_second
FROM level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_interval_second < avg_interval_first