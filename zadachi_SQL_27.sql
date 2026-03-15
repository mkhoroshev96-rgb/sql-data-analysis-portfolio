-- 160. «Знайди клієнтів, у яких є СЕРІЇ підряд ідучих замовлень, 
-- де кожне наступне замовлення дорожче за попереднє, і довжина серії ≥ 3.»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 0 ELSE 1 END as break_flag
FROM level2),
level4 as(SELECT *
       ,SUM(break_flag) OVER (partition by customer_id order by order_date) as series_id
FROM level3)
SELECT customer_id
       ,series_id 
	   ,COUNT(*) as series_length
	   ,MIN(sum_chek) as min_chek
	   ,MAX(sum_chek) as max_chek
	   ,MIN(order_date) as min_date
	   ,MAX(order_date) as max_date
FROm level4
GROUP BY customer_id, series_id
HAVING COUNT(*) >= 3
ORDER BY customer_id

-- 161. «Для кожного клієнта обчисли середній час між його замовленнями.
-- Визнач групи клієнтів за їхньою “частотою” покупок:
-- Fast — якщо середній інтервал < 20 днів
-- Medium — від 20 до 50 днів
-- Slow — > 50 днів

WITH level1 as(SELECT DISTINCT order_date
       ,customer_id
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_date
       ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM level1),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(interval)::numeric,2) as avg_interval
FROM level3
GROUP BY customer_id)
SELECT *
       ,case when avg_interval < 20 Then 'fast'
	   when avg_interval >= 20 AND avg_interval < 50 THEN 'medium'
	   when avg_interval >= 50 THEN 'slow'
	   END as gradation
FROm level4

-- 162. «Для кожного клієнта визнач переходи між категоріями товарів
-- від одного замовлення до наступного.
-- Знайди ТОП-5 найпоширеніших переходів по всій базі»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_name
	   ,quantity
	   ,MAX(quantity) over (partition by customer_id,order_id order by order_date) as max_quantity
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING(category_id)),
level2 as(SELECT *
       ,LEAD(category_name) OVER(partition by customer_id order by order_date) as next_category
FROM level1
WHERE quantity = max_quantity),
level3 as(SELECT *
       ,category_name || ' ' || next_category as perehid
FROM level2),
level4 as(SELECT perehid
       ,COUNT(*) as count_orders
FROm level3
where perehid is not null
GROUP BY perehid),
level5 as(SELECT *
       ,dense_rank() OVER (order by count_orders DESC) as rn
FROM level4)
SELECT *
FROM level5
where rn <= 5

-- 163. «Сесії покупок: знайти кластери замовлень»

WITH level1 as (SELECT DISTINCT order_date
       ,customer_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_date),
level2 as(SELECT customer_id
       ,order_date 
	   ,sum_chek
	   ,sum_quantity
       ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_order_date
FROM level1),
level3 as(SELECT *
       ,order_date - prev_order_date as interval
FROM level2),
level4 as(SELECT *
       ,case when interval <= 3 THEN 0 ELSE 1 END as flag_session
FROM level3),
level5 as(SELECT *
       ,SUM(flag_session) OVER (partition by customer_id order by order_date) as session_id
FROM level4)
SELECT customer_id
       ,session_id
	   ,COUNT(*) as count_session
	   ,SUM(sum_chek) as total_revenue
	   ,MAX(order_date) as max_order_date
	   ,MIN(order_date) as min_order_date
	   ,MAX(order_date) - MIN(order_date) as session_duration_days
FROm level5
GROUP BY customer_id,session_id
ORDER BY customer_id,session_id





