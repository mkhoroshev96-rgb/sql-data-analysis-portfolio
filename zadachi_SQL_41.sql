-- 253. “Клієнти з ефектом раннього піку”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,NTILE(3) OVER (partition by customer_id order by order_date) as ntile_3
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1
where count_order >= 5)
SELECT *
FROM level2
WHERE sum_chek = max_chek AND ntile_3 = 1

-- 254. “Клієнти з перекошеним кошиком”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(SUM(chek) OVER (partition by customer_id,order_id)::numeric,2) as sum_chek_per_order
FROM level1),
level3 as(SELECT *
       ,ROUND(((chek / sum_chek_per_order)*100),2) as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio >= 70

-- 255. “Клієнти з нестабільним якорем”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek 
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek_per_order
	   ,COUNT(product_id) OVER (partition by customer_id,product_id) as count_product
FROM level1),
level3 as(SELECT *
       ,ROUND(((chek / sum_chek_per_order)*100),2) as ratio
FROM level2),
level4 as(SELECT *
       ,case when ratio >= 60 THEN 1 ELSE 0 END as ratio_60
	   ,case when ratio <= 20 THEN 1 ELSE 0 END as ratio_20
FROm level3
WHERE count_product >= 3),
level5 as(SELECT *
       ,SUM(ratio_60) OVER (partition by customer_id,product_id) as sum_ratio_60
	   ,SUM(ratio_20) OVER (partition by customer_id,product_id) as sum_ratio_20
FROm level4)
SELECT *
FROM level5
WHERE sum_ratio_60 >=1 AND sum_ratio_20 >= 1

-- 256. “Клієнти з ілюзією вигідної знижки”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(avg_discount) OVER (partition by customer_id)::numeric,4) as avg_discount_per_customer
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_per_customer
FROM level1)
SELECT *
FROm level2
WHERE avg_discount > avg_discount_per_customer AND sum_chek < avg_chek_per_customer

-- 257. “Клієнти з ефектом нестабільного кошика”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
FROM level1
WHERE count_order >= 5),
level3 as(SELECT DISTINCT customer_id
       ,avg_quantity
	   ,max_quantity
	   ,ROUND((max_quantity / avg_quantity)::numeric,2) as ratio
FROM level2)
SELECT *
FROm level3
WHERE ratio >= 2

-- 258. “Клієнти з ефектом різкого повернення”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level2),
level4 as(SELECT *
       ,MAX(order_date) FILTER (where interval=max_interval) OVER (partition by customer_id) as max_date
FROM level3),
level5 as(SELECT *
       ,case when order_date < max_date THEN '1_before'
	   when order_date > max_date THEN '2_after'
	   else 'pause' END as flag_date
FROm level4),
level6 as(SELECT *
       ,dense_rank() OVER (partition by customer_id,flag_date order by order_date) as rank_date
FROM level5
WHERE flag_date IN ('1_before','2_after')),
level7 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_date = '1_before')::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE flag_date = '2_after' AND rank_date = 1)::numeric,2) as avg_quantity_after
FROM level6
GROUP By customer_id)
SELECT *
FROM level7
WHERE avg_quantity_before is not null AND avg_quantity_after is not null
AND avg_quantity_after >= 2 * avg_quantity_before

-- 259. «Клієнти з ефектом “останнього пострілу”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id,order_date),
level2 as(SELECT *
       ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date DESC) as next_1
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,LEAD(next_1) OVER (partition by customer_id order by order_date DESC) as next_2
FROM level2),
level4 as(SELECT *
       ,LEAD(next_2) OVER (partition by customer_id order by order_date DESC) as next_3
FROM level3),
level5 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek)
FROM level4
GROUP BY customer_id),
level6 as(SELECT *
FROM level4
JOIN level5 USING(customer_id)),
level7 as(SELECT *
       ,case when sum_quantity < next_1 AND sum_quantity < next_2 AND sum_quantity < next_3 THEN 'yes'
	   ELSE 'no' END as flag_quantity
FROM level6
WHERE rn_date = 1)
SELECT *
FROM level7
WHERE flag_quantity = 'yes' AND sum_chek >= percentile_cont

-- 260. Знайди клієнтів, у яких:є мінімум 3 замовлення
-- останнє замовлення має
-- меншу кількість товарів, ніж перше замовлення

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROW_number() OVER (partition by customer_id order by order_date) as rn_date
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_date_invert
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
          ,ROUND(AVG(sum_quantity) FILTER (WHERE rn_date = 1)::numeric,0) as first_order
		  ,ROUND(AVG(sum_quantity) FILTER (WHERE rn_date_invert = 1)::numeric,0) as last_order
FROM level1
GROUP BY customer_id)
SELECT *
FROm level2
where first_order > last_order