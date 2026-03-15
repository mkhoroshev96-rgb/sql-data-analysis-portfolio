-- 358. «Замовлення з внутрішнім перекосом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek
FROM level1),
level3 aS(SELECT *
       ,ROUND(((chek / sum_chek) * 100)::numeric,2) as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio >= 70

-- 359. «Замовлення з ілюзією знижки»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(AVG(discount)::numeric,2) as avg_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(avg_discount) OVER (partition by customer_id)::numeric,2) as avg_discount_customer
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
FROm level1)
SELECT *
FROM level2
WHERE avg_discount > avg_discount_customer AND sum_chek < avg_chek_customer

-- 360. «Замовлення, що ламають портрет клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
FROM level1
JOIN level2 USING (customer_id))
SELECT *
FROM level3
WHERE sum_quantity = max_quantity And sum_chek < median_chek

-- 361. «Клієнти з перевернутою стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROm level1
JOIN level2 USING(customer_id)
WHERE median_chek > avg_chek
ORDER BY customer_id, order_id),
level4 as(SELECT *
       ,ROUND(((max_chek / total_revenue) * 100)::numeric,2) as ratio
FROm level3)
SELECT *
FROm level4
WHERE ratio <= 30

-- 362. «Клієнти з хибним поверненням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1),
level3 as(SELECT *
       ,MAX(interval) OVER (partition by customer_id) as max_interval
FROm level2),
level4 as(SELECT *
       ,MAX(case when interval = max_interval THEN order_date END) OVER (partition by customer_id) as date_max_interval
FROM level3),
level5 as(SELECT *
       ,case when order_date < date_max_interval THEN '1_before'
	   when order_date > date_max_interval THEN '2_after'
	   when order_date = date_max_interval THEN 'pause'
	   END as gradation
FROM level4),
level6 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id,gradation order by order_date) as rn
FROm level5
WHERE gradation IN ('1_before','2_after') AND prev_date is not null),
level7 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '1_before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '2_after' AND rn = 1)::numeric,2) as avg_chek_after_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = '2_after' AND rn = 2)::numeric,2) as avg_chek_after_second
FROm level6
GROUP By customer_id),
level8 as(SELECT *
FROm level7
WHERE avg_chek_before is not null AND avg_chek_after_first is not null
AND avg_chek_after_second is not null)
SELECT *
FROm level8
WHERE avg_chek_before > avg_chek_after_first AND avg_chek_after_second > avg_chek_before

-- 363. «Клієнти з хибною економією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,case when avg_price > prev_price THEN 1 ELSE 0 END as flag_price
	   ,case when sum_chek <= prev_chek THEN 1 ELSE 0 END as flag_chek
FROM level2),
level4 as(SELECT *
       ,case when flag_price = 1 AND flag_chek = 1 THEN 0 ELSE 1 END as flag_price_chek
FROM level3),
level5 as(SELECT *
       ,SUM(flag_price_chek) OVER (partition by customer_id order by order_date) as sum_rn
FROM level4),
level6 as(SELECT customer_id 
       ,sum_rn
	   ,COUNT(sum_rn) as count_sum_rn
FROm level5
GROUP By customer_id, sum_rn),
level7 as(SELECT *
       ,count_sum_rn - 1 as real_count_sum_rn
FROM level6)
SELECT *
From level7
WHERE real_count_sum_rn >= 3

-- 364. «Клієнти з перерваною активністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date 
FROm orders),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1),
level3 as(SELECT *
          ,LEAD(interval) OVER (partition by customer_id order by order_date) as next_interval
FROm level2),
level4 as(SELECT *
FROm level3
WHERE interval is not null),
level5 as(SELECT *
       ,LEAD(next_interval) OVER (partition by customer_id order by order_date) as next_2_interval
FROm level4),
level6 as(SELECT *
FROm level5),
level7 as(SELECT *
       ,case when interval <= 30 AND next_interval <= 30 AND next_2_interval > 30 THEN 'yes'
	   ELSE 'no' END as flag_intervals
FROm level6
WHERE next_interval is not null AND next_2_interval is not null)
SELECT *
FROm level7
WHERE flag_intervals = 'yes'

-- 365. «Клієнти зі стабільною серією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROm level1),
level3 as(SELECT *
       ,case when prev_quantity > sum_quantity THEN 1 ELSE 0 END as flag_quantity
FROm level2),
level4 as(SELECT *
       ,SUM(flag_quantity) OVER (partition by customer_id order by order_date) as sum_flag
FROM level3),
level5 as(SELECT customer_id
       ,sum_flag
	   ,COUNT(sum_flag) as count_sum_flag
FROM level4
GROUP By customer_id,sum_flag),
level6 as(SELECT *
       ,count_sum_flag - 1 as real_count_sum_flag
FROM level5)
SELECT *
FROm level6
WHERE real_count_sum_flag >= 3