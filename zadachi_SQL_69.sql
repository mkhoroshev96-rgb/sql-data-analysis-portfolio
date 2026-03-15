-- 438. «Клієнт із інверсією цінності асортименту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(DISTINCT product_id) as count_unik_prod
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) over (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) over (partition by customer_id)::numeric / 2),2) as middle_point
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as (SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by count_unik_prod, order_id) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by count_unik_prod DESC, order_id DESC) as rn_invert
	   ,ROUND((sum_chek / sum_quantity)::numeric,2) as price
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn = rn_invert THEN 0 ELSE 1 END as flag_null
FROM level2),
level4 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level3
WHERE flag_null = 1),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(AVG(price) FILTER (WHERE halfs = 'first')::numeric,2) as avg_price_first
	   ,ROUND(AVG(price) FILTER (WHERE halfs = 'second')::numeric,2) as avg_price_second
	   ,ROUND(AVG(count_unik_prod) FILTER (WHERE halfs = 'first')::numeric,2) as avg_unik_prod_first
	   ,ROUND(AVG(count_unik_prod) FILTER (WHERE halfs = 'second')::numeric,2) as avg_unik_prod_second
FROM level4
GROUP By customer_id)
SELECT *
FROM level5
WHERE avg_chek_second > avg_chek_first
AND avg_price_second < avg_price_first
AND avg_unik_prod_second >= 1.5 * avg_unik_prod_first

-- 439. «Клієнт з ефектом помилкової адаптації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,ROUND((sum_chek / sum_quantity),2) as price
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,LAG(price) OVER (partition by customer_id order by order_date) as prev_price
FROm level2),
level4 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
	   ,price - prev_price as delta_price
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_before
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_after
FROM level3),
level5 as(SELECT *
       ,case when delta_chek > 0 AND delta_price < 0 THEN 1 ELSE 0 END as flag_che_pri
FROM level4),
level6 as(SELECT *
       ,SUM(flag_che_pri) OVER (partition by customer_id) as sum_flag
	   ,count_order - 1 as real_count_order
FROm level5),
level7 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE rn_before <= 3)::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE rn_after <= 3)::numeric,2) as avg_chek_after
	   ,ROUND(AVG(price) FILTER (WHERE rn_before <= 3)::numeric,2) as avg_price_before
	   ,ROUND(AVG(price) FILTER (WHERE rn_after <= 3)::numeric,2) as avg_price_after
FROm level6
GROUP By customer_id),
level8 as(SELECT *
       ,ROUND((sum_flag::numeric / real_count_order::numeric),2) as ratio
FROm level6
JOIN level7 USING (customer_id))
SELECT *
FROM level8
WHERE ratio >= 0.6 AND avg_chek_after > avg_chek_before AND avg_price_after <= avg_price_before

-- 440. «Клієнт із зламаною інерцією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1),
level3 as(SELECT *
       ,ABS(sum_chek - prev_chek) as delta_prev_chek
	   ,ABS(sum_chek - avg_chek) as delta_avg_chek
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,case when delta_prev_chek < delta_avg_chek THEN 1
	   when delta_prev_chek > delta_avg_chek then 0
	   END as flag_delta
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level3),
level5 as(SELECT *
       ,SUM(flag_delta) OVER (partition by customer_id) as sum_flag_delta
FROM level4),
level6 as(SELECT *
       ,ROUND((sum_flag_delta::numeric / count_order::numeric),2) as ratio
FROm level5)
SELECT *
FROM level6
WHERE ratio > 0.5 AND (sum_chek = max_chek AND rn_invert <> 1 AND flag_delta = 0)

-- 441. «Клієнт, у якого “зламалась пам’ять”»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when ABS(sum_chek - prev_chek) < ABS(sum_chek - avg_chek) THEN 0
	   ELSE 1 END as flag_cheks
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,SUM(flag_cheks) OVER (partition by customer_id) as sum_flag_cheks
FROM level3)
SELECT *
FROm level4
WHERE sum_flag_cheks = 1

-- 442. «Замовлення без впливу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,COUNT(product_id) OVER (partition by customer_id, order_id) as count_item_order
FROM orders
JOIn order_details USING (order_id)),
level2 as(SELECT customer_id
       ,product_id
	   ,COUNT(product_id) as count_bay_product
FROm level1
GROUP By customer_id, product_id
ORDER BY customer_id),
level3 as(SELECT *
FROm level1
JOIN level2 USING (customer_id, product_id)),
level4 as(SELECT product_id
       ,COUNT(product_id) as bay_product_total
FROM level3
GROUP BY product_id)
SELECT *
FROM level3
JOIn level4 USING (product_id)
WHERE count_item_order = 1 AND count_bay_product = 1 AND bay_product_total > 1