-- 669. «Клієнт із ефектом ілюзії середнього чека»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(MAX(sum_chek) OVER (partition by customer_id)::numeric,2) as max_chek
FROm level2
JOIN level3 USING (customer_id))
SELECT *
FROM level4
WHERE median_chek <= 0.6 * avg_chek AND max_chek >= 2.5 * avg_chek

-- 670. «Клієнт із ефектом прихованої волатильності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_product
FROM level1
GROUP BY customer_id, order_id),
level3 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, order_id) as sum_quantity
FROm level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT DISTINCT customer_id
       ,order_id
	   ,count_unik_product
	   ,sum_quantity
FROm level3),
level5 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(STDDEV(sum_quantity) OVER (partition by customer_id)::numeric,2) as stddev_quantity
	   ,ROUND(AVG(count_unik_product) OVER (partition by customer_id)::numeric,2) as avg_count_unik_product
	   ,ROUND(STDDEV(count_unik_product) OVER (partition by customer_id)::numeric,2) as stddev_unik_product
FROm level4)
SELECT *
FROm level5
WHERE stddev_quantity <= 0.15 * avg_quantity AND stddev_unik_product >= 0.5 * avg_count_unik_product

-- 671. «Ефект штучної стабільності клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUnd(STDDEV(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as stddev_chek_first
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as stddev_chek_second
FROm level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_chek_second > avg_chek_first and stddev_chek_first > stddev_chek_second

-- 672. «Клієнт із хибною точкою стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek 
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id order by order_date) as sum_chek_cumm
	   ,COUNT(order_id) OVER (partition by customer_id order by order_date) as cum_count
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROUND(((sum_chek_cumm - sum_chek) / (cum_count - 1))::numeric,2) as avg_chek_ohne_order
FROm level2
WHERE cum_count > 1),
level4 as(SELECT *
       ,case when sum_chek > avg_chek_ohne_order THEN 1 ELSE 0 END as flag_chek
FROm level3),
level5 as(SELECT *
       ,MAX(case when flag_chek = 1 THEN order_date END) OVER (partition by customer_id) as max_flag_chek
FROm level4)
SELECT *
FROm level5
WHERE order_date = max_flag_chek

-- 673. «Точка незворотного згасання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id order by order_date) as cumm_max_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,LAG(cumm_max_chek) OVER (partition by customer_id order by order_date) as prev_cumm_max_chek
FROm level2),
level4 as(SELECT *
       ,case when sum_chek > prev_cumm_max_chek THEN 1 ELSE 0 END as flag_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level3),
level5 as(SELECT *
       ,MAX(case when flag_chek = 1 THEN order_date END) OVER (partition by customer_id) as max_date
FROm level4)
SELECT *
FROm level5
WHERE order_date = max_date OR (rn_invert = 1 AND flag_chek = 0) AND (rn_invert = 2 AND flag_chek = 1)

-- 674. «Клієнт з фальшивим плато»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_chek) FROM level1) as global_median
FROM level1),
level3 as(SELECT *
       ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as next_1_chek
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as next_2_chek
FROM level2
WHERE count_order >= 10 AND avg_chek > global_median),
level4 as(SELECT *
       ,case when sum_chek < avg_chek AND next_1_chek < avg_chek AND next_2_chek < avg_chek THEN 1
	   ELSE 0 END as flag_chek
FROM level3)
SELECT *
FROM level4
WHERE flag_chek = 1

-- 675. «Клієнт з перевернутою стабільністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MIN(sum_chek) OVER (partition by customer_id order by order_date) as min_chek_cumm
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,case when sum_chek > min_chek_cumm THEN 1 ELSE 0 END as flag_min_chek
FROm level2),
level4 as(SELECT *
       ,MAX(case when flag_min_chek = 0 THEN order_date END) OVER (partition by customer_id) as max_date_min_chek
FROM level3)
SELECT *
FROM level4
WHERE order_date = max_date_min_chek




