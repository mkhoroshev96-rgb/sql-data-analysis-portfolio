-- 758. «Клієнт із ефектом прихованого витіснення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as next_1_chek
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as next_2_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > next_1_chek AND next_2_chek > next_1_chek AND next_2_chek > sum_chek THEN 1
	   ELSE 0 END as gradation
FROM level2
WHERE next_2_chek is not null)
SELECT *
FROM level3
WHERE gradation = 1

-- 759. «Клієнт із прихованим парадоксом стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,SUM(unit_price) as avg_price
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
	   ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_price
FROM level1),
level3 as(SELECT *
       ,case when next_quantity >= sum_quantity THEN 1 ELSE 0 END as flag_quantity
	   ,case when avg_price >= next_price THEN 1 ELSE 0 END as flag_price
FROM level2
WHERE next_quantity is not null AND next_price is not null),
level4 as(SELECT *
       ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
	   ,SUM(flag_price) OVER (partition by customer_id) as sum_flag_price
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level3)
SELECT *
FROM level4
WHERE sum_flag_quantity = real_count_order AND sum_flag_price = real_count_order

-- 760. «Клієнт із латентною інваріантністю розподілу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,case when rn <= 3 THEN 'first_orders'
	   when rn_invert <= 3 THEN 'last_orders'
	   else 'other' END as gradation
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,SUM(sum_chek) FILTER (WHERE gradation = 'first_orders') OVER (partition by customer_id) as sum_chek_first_orders
	   ,SUM(sum_chek) FILTER (WHERE gradation = 'last_orders') OVER (partition by customer_id) as sum_chek_last_orders
FROM level2
WHERE gradation IN ('first_orders', 'last_orders')),
level4 as(SELECT *
       ,ROUND((sum_chek_first_orders / total_revenue),4) as ratio_first
	   ,ROUND((sum_chek_last_orders / total_revenue),4) as ratio_last
FROM level3),
level5 as(SELECT *
       ,ABS(ratio_first - ratio_last) as abs_diff_ratio
FROM level4)
SELECT *
FROM level5
WHERE abs_diff_ratio <= 0.05

-- 761. «Клієнт із латентною стабільністю відносної позиції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
FROM level1),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,LEAD(rn_chek) OVER (partition by customer_id order by order_date) as next_rn_chek
FROM level2),
level4 as(SELECT *
       ,ABS(next_rn_chek - rn_chek) as diff_rn
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level3
WHERE next_rn_chek is not null),
level5 as(SELECT *
       ,case when diff_rn <= 1 THEN 1 ELSE 0 END as flag_diff_rn
FROM level4),
level6 as(SELECT *
       ,SUM(flag_diff_rn) OVER (partition by customer_id) as sum_flag_diff_rn
FROm level5)
SELECT *
FROM level6
WHERE real_count_order = sum_flag_diff_rn

-- 762. «Індекс траєкторійної нестабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 14),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,case when delta_chek > 0 THEN 'plus'
	   when delta_chek < 0 THEN 'minus'
	   when delta_chek = 0 THEN 'equal'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation
FROM level4
WHERE gradation IN ('plus', 'minus')),
level6 as(SELECT *
       ,case when (gradation = 'plus' AND prev_gradation = 'minus') OR (gradation = 'minus' AND prev_gradation = 'plus') THEN 1
	   ELSE 0 END as flag_gradation
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count_order
FROM level5
WHERE prev_gradation is not null),
level7 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id) as sum_flag_gradation
FROM level6),
level8 as(SELECT DISTINCT customer_id
       ,sum_flag_gradation
	   ,real_count_order
FROM level7),
level9 as(SELECT *
       ,ROUND((sum_flag_gradation::numeric / real_count_order::numeric),4) as ratio
FROm level8)
SELECT *
       ,case when ratio > 0.8 THEN 'very_high'
	   when ratio between 0.6 AND 0.8 THEN 'high'
	   when ratio between 0.4 AND 0.6 THEN 'normal'
	   when ratio between 0.2 AND 0.4 THEN 'low'
	   when ratio < 0.2 THEN 'very_low'
	   END as classification
FROM level9

-- 763. «Індекс структурного зламу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,NTILE(4) OVER (partition by customer_id order by order_date) as ntile_4
FROM level1
WHERE count_order >= 16),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id, ntile_4)::numeric,2) as avg_chek_ntile
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,ntile_4
	   ,avg_chek_ntile
FROM level3
ORDER BY customer_id, ntile_4),
level5 as(SELECT *
       ,LAG(avg_chek_ntile) OVER (partition by customer_id order by ntile_4) as prev_avg_chek_ntile
FROM level4),
level6 as(SELECT *
       ,ABS(avg_chek_ntile - prev_avg_chek_ntile) as abs_diff_avg_chek
FROM level5
WHERE prev_avg_chek_ntile is not null),
level7 as(SELECT *
       ,MAX(abs_diff_avg_chek) OVER (partition by customer_id) as max_abs_diff_avg_chek
fROM level6)
SELECT *
FROM level7
WHERE abs_diff_avg_chek = max_abs_diff_avg_chek

-- 764. «Індекс прихованої концентрації»

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
       ,SUM(chek) OVER (partition by customer_id, category_id) as sum_chek_per_category
	   ,SUM(chek) OVER (partition by customer_id) as total_revenue
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,category_id
	   ,sum_chek_per_category
	   ,total_revenue
FROM level2),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id ORDER BY sum_chek_per_category DESC) as rn_chek_category
FROM level3),
level5 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id),
level6 as(SELECT *
       ,ROUND((sum_chek_per_category / total_revenue),4) as ratio
FROM level4
JOIN level5 USING (customer_id) 
WHERE count_order >= 15 AND rn_chek_category <= 2),
level7 as(SELECT customer_id
       ,ROUND(AVG(ratio) FILTER (WHERE rn_chek_category = 1)::numeric,4) as max_share
	   ,ROUND(AVG(ratio) FILTER (WHERE rn_chek_category = 2)::numeric,4) as second_share
FROM level6
GROUP By customer_id)
SELECT *
       ,max_share - second_share as dominance_gap
FROM level7

-- 765. «Індекс порогової поведінки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(discount)::numeric,2) as avg_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high_median'
	   when sum_chek < median_chek THEN 'low_median'
	   when sum_chek = median_chek THEN 'equalk_median'
	   END as groups
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 16),
level4 as(SELECT *
       ,ROUND(AVG(avg_discount) FILTER (WHERE groups = 'high_median') OVER (partition by customer_id)::numeric,4) as avg_discount_high_median
	   ,ROUND(AVG(avg_discount) FILTER (WHERE groups = 'low_median') OVER (partition by customer_id)::numeric,4) as avg_discount_low_median
FROM level3
WHERE groups IN ('high_median', 'low_median')),
level5 as(SELECT DISTINCT customer_id
       ,avg_discount_high_median
	   ,avg_discount_low_median
FROm level4)
SELECT *
       ,avg_discount_high_median - avg_discount_low_median as threshold_bias
FROm level5