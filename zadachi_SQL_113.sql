-- 752. «Клієнт із прихованим порушенням монотонності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_price
FROM level1),
level3 as(SELECT *
       ,avg_price - next_price as delta_price
FROM level2
WHERE next_price is not null),
level4 as(SELECT *
       ,case when delta_price > 0 THEN 'delta_plus'
	   when delta_price < 0 THEN 'delta_minus'
	   when delta_price = 0 THEN 'delta_equal'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
FROM level4),
level6 as(SELECT *
       ,case when (gradation = 'delta_plus' AND next_gradation = 'delta_minus') OR (gradation = 'delta_minus' AND next_gradation = 'delta_plus') THEN 1 
	   ELSE 0 END as flag_delta
FROM level5
WHERE next_gradation is not null),
level7 as(SELECT *
       ,SUM(flag_delta) OVER (partition by customer_id) as sum_flag_delta
FROM level6)
SELECT *
FROM level7
WHERE sum_flag_delta = 1

-- 753. «Клієнт із латентним домінуванням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, order_id) as total_revenue_order
	   ,SUM(chek) OVER (partition by customer_id, order_id, category_id) as sum_chek_per_category_order
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,sum_chek_per_category_order
	   ,total_revenue_order
FROM level2
ORDER BY customer_id),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, order_id order by sum_chek_per_category_order DESC) as rn_sum_chek_per_category_order
FROM level3),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM level4
WHERE rn_sum_chek_per_category_order = 1),
level6 as(SELECT customer_id
       ,category_id
	   ,COUNT(category_id) as count_category
FROM level5
GROUP BY customer_id, category_id),
level7 as(SELECT *
       ,count(order_id) OVER (partition by customer_id) as count_order
FROM level5
JOIN level6 USING (customer_id, category_id)),
level8 as(SELECT *
       ,ROUND((count_category::numeric / count_order::numeric),2) as ratio
FROM level7),
level9 as(SELECT *
       ,MAX(ratio) OVER (partition by customer_id) as max_ratio
FROM level8),
level10 as(SELECT *
       ,MAX(case when ratio = max_ratio THEN category_id END) OVER (partition by customer_id) as top_category
FROM level9
WHERE max_ratio > 0.5),
level11 as(SELECT *
       ,FIRST_VALUE(category_id) OVER (partition by customer_id order by order_date) as first_category_id
FROM level10)
SELECT *
FROM level11
WHERE top_category <> first_category_id

-- 754. «Клієнт із прихованою симетрією структури»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
FROM orders
JOIN order_details USING (order_id)
JOIN products USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(DISTINCT category_id) as count_unik_category
FROM level1
GROUP BY customer_id, order_id, order_date),
level3 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
	   ,count_unik_category
FROM level1
JOIN level2 USING (customer_id, order_id, order_date)),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,count(order_id) OVER (partition by customer_id) as count_order
FROm level3),
level5 as(SELECT a.customer_id
       ,a.order_id
	   ,b.order_id
	   ,a.order_date
	   ,b.order_date
	   ,a.count_unik_category as a_unik
	   ,b.count_unik_category as b_unik
	   ,a.rn
	   ,b.rn
	   ,a.count_order
FROM level4 a
JOIN level4 b ON a.customer_id = b.customer_id
AND a.rn = b.count_order - b.rn + 1),
level6 as(SELECT *
       ,case when a_unik = b_unik THEN 1 ELSE 0 END as flags
FROM level5),
level7 as(SELECT *
       ,SUM(flags) OVER (partition by customer_id) as sum_flags
FROM level6)
SELECT *
FROM level7
WHERE count_order = sum_flags

-- 755. «Токсична стабільність»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,4) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,4) as stddev_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROUND((stddev_chek / avg_chek),4) as cv
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,stddev_chek
	   ,cv
FROM level3)
SELECT *
FROM level4
ORDER BY cv
LIMIT 10

-- 756. «Ілюзія стабільного зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,halfs
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median
FROM level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIn level3 USING (customer_id, halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(median) FILTER (WHERE halfs = 'first')::numeric,2) as median_first
	   ,ROUND(AVG(median) FILTER (WHERE halfs = 'second')::Numeric,2) as median_second
FROM level4
GROUP BY customer_id)
SELECT *
FROm level5
WHERE median_second > median_first

-- 757. «Стабільність як маска хаосу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::Numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id order by order_date) as cumm_max_chek
fROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROUND(((sum_chek - cumm_max_chek) / cumm_max_chek)::numeric,4) as drawdown
FROM level2),
level4 as(SELECT *
       ,MIN(drawdown) OVER (partition by customer_id) as min_drawdown
FROM level3)
SELECT DISTINCT customer_id
       ,min_drawdown
FROM level4