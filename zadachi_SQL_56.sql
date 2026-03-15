-- 350. «Замовлення з інверсною цінністю кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROM level1
WHERE count_order >= 5
GROUP By customer_id),
level3 as(SELECT *
FROm level1
JOIN level2 USING (customer_id))
SELECT *
FROm level3
WHERE sum_quantity < median_quantity AND sum_chek > avg_chek

-- 351. «Клієнти з глобально мінімальним переломним замовленням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,MIN(case when sum_chek = min_chek THEN order_date END) OVER (partition by customer_id) as min_chek_date 
FROm level2),
level4 as(SELECT *
       ,case when order_date < min_chek_date THEN '1_before'
	   when order_date > min_chek_date THEN '2_after'
	   when order_date = min_chek_date THEN 'pause'
	   END as gradation
FROM level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '1_before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '2_after')::numeric,2) as avg_chek_after
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'pause')::numeric,2) as avg_chek_pause
FROm level4
GROUP By customer_id),
level6 as(SELECT *
FROM level5
WHERE avg_chek_before is not null AND avg_chek_after is not null)
SELECT *
FROM level6
WHERE avg_chek_pause < avg_chek_before AND avg_chek_pause < avg_chek_after

-- 352. «Клієнти з ефектом помилкового апгрейду»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1
WHERE count_order >= 5
ORDER BY customer_id, order_date),
level3 as(SELECT *
       ,MAX(case when sum_chek = max_chek THEN order_date END) OVER (partition by customer_id) as max_chek_date
FROm level2),
level4 as(SELECT *
       ,case when order_date < max_chek_date THEN 'other'
	   when order_date > max_chek_date THEN 'after'
	   when order_date = max_chek_date Then 'max_chek'
	   END as gradation
FROm level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'max_chek')::numeric,2) as avg_chek_max
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation ='after')::numeric,2) as avg_chek_after
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = 'max_chek')::numeric,2) as avg_quantity_max
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE gradation = 'after')::numeric,2) as avg_quantity_after
FROM level4
WHERE gradation In ('max_chek', 'after')
GROUP By customer_id),
level6 as(SELECT *
FROM level5
WHERE avg_chek_after is not null AND avg_quantity_after is not null)
SELECT *
FROM level6
WHERE avg_chek_max >= avg_chek_after AND avg_quantity_max < avg_quantity_after 

-- 353. «Клієнти з ілюзією стабільності»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(((sum_chek / prev_chek) * 100)::numeric,2) as diff_chek
FROm level2),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level3
GROUP By customer_id),
level5 as(SELECT *
       ,ROUND(ABS((median_chek - avg_chek) / median_chek)::numeric,2) as diff_median_avg
FROM level3
JOIN level4 USING(customer_id))
SELECT *
FROM level5
WHERE (diff_chek >= 150 OR diff_chek <= 50) AND diff_median_avg <= 0.05

-- 354. «Клієнти з фальшивою регулярністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
FROM level2
WHERE prev_date is not null),
level4 as(SELECT customer_id
       ,ROUND(AVG(interval)::numeric,2) as avg_interval
	   ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median_interval
FROm level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND(ABS((median_interval - avg_interval) / median_interval)::numeric,2) as diff_median_avg
	   ,MAX(interval) OVER (partition by customer_id) as max_interval
FROM level3
JOIn level4 USING (customer_id)),
level6 as(SELECT *
       ,ROUND((max_interval::numeric / median_interval::numeric),2) as diff_max_median
FROM level5
WHERE diff_median_avg <= 0.1)
SELECT *
FROM level6
WHERE diff_max_median >= 3

-- 355. «Клієнти з ефектом зміни уподобань»

WITH level1 as(SELECT customer_id
       ,category_id
	   ,order_id
	   ,quantity
FROm orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)
ORDER BY customer_id, category_id),
level2 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, category_id) as sum_qnt_category
FROM level1),
level3 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by sum_qnt_category DESC) as rank_sum_qnt
FROm level2),
level4 as(SELECT customer_id
       ,rank_sum_qnt
	   ,ROUND(AVG(quantity)::numeric,2) as avg_quantity
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by quantity)::numeric,2) as median_quantity
FROM level3
WHERE rank_sum_qnt <= 2
GROUP By customer_id, rank_sum_qnt),
level5 as(SELECT *
       ,ROUND(ABS((median_quantity - avg_quantity) / median_quantity)::numeric,2) as diff
FROM level3
JOIN level4 USING (customer_id,rank_sum_qnt)),
level6 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP BY customer_id),
level7 as(SELECT *
FROM level5
JOIn level6 USING (customer_id)),
level8 as(SELECT *
FROM level7
WHERE count_order >= 6),
level9 as(SELECT customer_id
       ,ROUND(AVG(avg_quantity) FILTER (WHERE rank_sum_qnt = 1)::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(avg_quantity) FILTER (WHERE rank_sum_qnt = 2)::numeric,2) as avg_quantity_second
FROM level8
WHERE diff <= 0.05
GROUP BY customer_id),
level10 as(SELECT *
       ,ROUND(ABS((avg_quantity_second - avg_quantity_first) / avg_quantity_second)::numeric,2) as diff_first_second
FROm level9
Where avg_quantity_first is not null AND avg_quantity_second is not null)
SELECT *
FROM level10
WHERE diff_first_second >= 1

-- 356. «Замовлення з парадоксом знижки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,2) as avg_discount
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(avg_discount) OVER (partition by customer_id)::numeric,2) as avg_discount_per_customer
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_per_customer
FROM level1)
SELECT *
FROM level2
WHERE avg_discount > avg_discount_per_customer AND sum_chek > avg_chek_per_customer

-- 357. «Замовлення з ілюзією вигідної ціни»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(avg_price) OVER (partition by customer_id)::numeric,2) as avg_price_per_customer
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_per_customer
FROM level1)
SELECT *
FROM level2
WHERE avg_price < avg_price_per_customer AND sum_chek > avg_chek_per_customer
