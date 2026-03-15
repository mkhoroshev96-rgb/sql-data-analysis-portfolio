-- 549. «Клієнт з ефектом маскованої деградації маржі»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount_per_order
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as revenue
	   ,ROUND(sum(unit_price * quantity)::numeric,2) as base_cost
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,ROUND((revenue / base_cost)::numeric,2) as margin_ratio
FROM level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,halfs
	   ,AVG(revenue) as avg_revenue
	   ,AVG(avg_discount_per_order) as avg_discount
	   ,percentile_cont(0.5) WITHIN GROUP (order by margin_ratio) as median_margin
FROM level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING(customer_id, halfs)),
level5 as(SELECT customer_id
       ,ROUND(AVG(avg_revenue) FILTER (WHERE halfs = 'first')::numeric,2) as avg_revenue_first
	   ,ROUND(AVG(avg_revenue) FILTER (WHERE halfs = 'second')::numeric,2) as avg_revenue_second
	   ,ROUND(AVG(avg_discount) FILTER (WHERE halfs = 'first')::numeric,2) as avg_discount_first
	   ,ROUND(AVG(avg_discount) FILTER (WHERE halfs = 'second')::numeric,2) as avg_discount_second
	   ,ROUND(AVG(median_margin) FILTER (WHERE halfs = 'first')::numeric,2) as median_margin_first
	   ,ROUND(AVG(median_margin) FILTER (WHERE halfs = 'second')::numeric,2) as median_margin_second
FROm level4
GROUP BY customer_id),
level6 as(SELECT *
       ,ROUND(ABS((avg_revenue_second - avg_revenue_first) / avg_revenue_first)::numeric,2) as diff_revenue
	   ,ROUND(ABS((avg_discount_second - avg_discount_first) / avg_discount_first)::numeric,2) as diff_discount
	   ,ROUND(((median_margin_first / median_margin_second)-1)::numeric,2) as diff_margin
FROm level5)
SELECT *
FROm level6
WHERE diff_revenue <= 0.05 AND diff_discount <= 0.05 AND diff_margin >= 0.1

-- 550. «Клієнт з ефектом локальної раціональності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,LEAD(delta_chek) OVER (partition by customer_id order by order_date) as next_delta
FROm level3),
level5 as(SELECT *
       ,case when delta_chek > 0 AND next_delta < 0 THEN 1 ELSE 0 END as flag_delta
FROm level4),
level6 as(SELECT *
       ,SUM(flag_delta) OVER (partition by customer_id) as sum_flag_delta
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_delta = 1) OVER (partition by customer_id)::numeric,2) as avg_chek_local_optima
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(delta_chek) OVER (partition by customer_id)::numeric,2) as avg_delta_chek
FROM level5)
SELECt *
FROm level6
WHERE sum_flag_delta >= 3 AND avg_chek_local_optima >= 1.3 * avg_chek AND avg_delta_chek < 0

-- 551. «Замовлення з ефектом зламаної причинності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek,1) OVER (partition by customer_id order by order_date) as prev_1_chek
	   ,LAG(sum_chek,2) OVER (partition by customer_id order by order_date) as prev_2_chek 
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,sum_chek - prev_1_chek as delta
	   ,prev_1_chek - prev_2_chek as prev_delta
FROm level2),
level4 as(SELECT *
	   ,case when sign(delta) = sign(prev_delta) AND ABS(delta) >= 1.5 * abs(prev_delta) THEN 1 ELSE 0 END as flag_sign
FROm level3
WHERE prev_2_chek is not null),
level5 as(SELECT *
       ,SUM(flag_sign) OVER (partition by customer_id) as sum_flag_sign
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_sign = 1) OVER (partition by customer_id)::numeric,2) as avg_chek_brocken
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level4)
SELECT *
FROm level5
WHERE sum_flag_sign >= 3 AND avg_chek_brocken >= 1.2 * avg_chek

-- 552. «Клієнт з ефектом зламаної памʼяті»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,MIN(case when sum_chek = max_chek THEN order_date END) OVER (partition by customer_id) as min_date_max_chek
FROm level2),
level4 as(SELECT *
       ,case when order_date < min_date_max_chek THEN 'before'
	   when order_date > min_date_max_chek THEN 'after'
	   when order_date = min_date_max_chek THEN 'equal'
	   END as gradation
FROm level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (where gradation = 'after')::numeric,2) as avg_chek_after
FROm level4
WHERE gradation IN ('before', 'after')
GROUP By customer_id),
level6 as(SELECT *
       ,ROUND(((avg_chek_before / avg_chek_after) - 1)::numeric,2) as diff_chek
FROm level5
WHERE avg_chek_before is not null AND avg_chek_after is not null)
SELECT *
FROm level6
WHERE diff_chek >= 0.15

-- 553. «Замовлення-паразит»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROm level1
WHERE count_order >= 6),
level3 as(SELECt *
       ,ROUND((sum_chek / total_revenue)::numeric,2) as ratio_chek
FROm level2)
SELECT *
FROm level3
WHERE ratio_chek >= 0.25 AND sum_chek < avg_chek

-- 554. «Клієнт з ефектом стабільної нестабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIn order_details USINg (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROm level1),
level3 as(SELECT *
       ,ROUND((stddev_chek / avg_chek)::numeric,2) as cv
	   ,ROUND(ABS((sum_chek - avg_chek) / avg_chek)::numeric,2) as diff_chek
FROm level2),
level4 as(SELECT *
       ,case when diff_chek <= 0.4 THEN 0 ELSE 1 END as flag_diff
FROm level3),
level5 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROm level4),
level6 as(SELECT *
       ,ROUND(AVG(cv) OVER ()::numeric,2) as gloabal_avg_cv
FROm level5)
SELECT *
FROm level6
WHERE sum_flag_diff = 0 AND cv > gloabal_avg_cv

-- 555. «Замовлення з ефектом втраченої ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((total_revenue - sum_chek) / (count_order - 1)::numeric,2) as avg_chek_ohne_order
FROM level2),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_ohne_order - avg_chek) / avg_chek)::numeric,2) as diff_chek_ohne_order
	   ,ROUND(ABS((sum_chek - avg_chek) / avg_chek)::numeric,2) as diff_chek_order
FROm level3)
SELECT *
FROm level4
WHERE diff_chek_ohne_order >= 0.2 AND diff_chek_order <= 0.3

-- 556. «Клієнт із зсувом норми»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level1
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,(SELECT percentile_cont (0.5) WITHIN group (order by median_chek) FROM level3) as global_median_chek
	   ,ROUND(ABS((sum_chek - median_chek) / median_chek)::numeric,2) as diff_median_chek
FROm level3),
level5 as(SELECT *
       ,case when diff_median_chek <= 0.25 THEN 1 ELSE 0 END as flag_median_chek
FROm level4),
level6 as(SELECT *
       ,SUM(flag_median_chek) OVER (partition by customer_id) as sum_flag_median_chek
FROm level5)
SELECT *
FROm level6
WHERE sum_flag_median_chek = count_order

-- 557. «Замовлення-хамелеон»

WITH level1 as(SELECT customer_id
       ,category_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id, category_id, order_id, order_date),
level2 as(SELECT category_id
       ,ROUND(AVG(chek)::numeric,2) as avg_chek_per_category
FROm level1
GROUP By category_id),
level3 as(SELECT *
FROm level1
JOIN level2 USING (category_id)),
level4 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,chek
	   ,avg_chek_per_category
	   ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek_customer
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,ROUND(AVG(sum_chek_customer)::numeric,2) as avg_chek
FROm level4
GROUP By customer_id),
level6 as(SELECT *
       ,case when (sum_chek_customer > avg_chek AND sum_chek_customer < avg_chek_per_category) OR (sum_chek_customer < avg_chek AND sum_chek_customer > avg_chek_per_category) THEN 1
	   ELSE 0 END as flags
FROm level4
JOIN level5 USING (customer_id))
SELECT *
FROM level6
WHERE flags = 1