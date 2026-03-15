-- 725. «Клієнт із ефектом зміщеного центру»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,SUM(sum_quantity) FILTER (WHERE halfs = 'first') as total_quantity_first
	   ,SUM(sum_quantity) FILTER (WHERE halfs = 'second') as total_quantity_second
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
FROM level3)
SELECT *
FROM level4
WHERE diff_chek <= 0.05 AND total_quantity_second > total_quantity_first

-- 726. «Клієнт із прихованою компенсацією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ABS(sum_chek - avg_chek) as abs_diff
	   ,case when sum_chek > avg_chek THEN 'high'
	   when sum_chek < avg_chek THEN 'low'
	   when sum_chek = avg_chek THEN 'equal'
	   END as gradation
FROM level2),
level4 as(SELECT *
       ,MAX(abs_diff) OVER (partition by customer_id) as max_abs_diff
FROM level3),
level5 as(SELECT *
       ,MAX(case when abs_diff = max_abs_diff AND gradation = 'high' THEN max_abs_diff END) over (partition by customer_id) as high_max_abs_diff
	   ,SUM(abs_diff) FILTER (WHERE gradation = 'low') OVER (partition by customer_id) as sum_abs_diff_low
FROM level4),
level6 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,max_abs_diff
	   ,high_max_abs_diff
	   ,sum_abs_diff_low
FROM level5),
level7 as(SELECT *
       ,case when high_max_abs_diff > sum_abs_diff_low THEN 1 ELSE 0 END as flags_high
FROM level6)
SELECT *
FROM level7
WHERE flags_high = 1

-- 727. «Клієнт із локальною нестабільністю при глобальній стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,next_chek - sum_chek as delta
FROm level2),
level4 as(SELECT *
       ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
	   ,ROUND(STDDEV(delta) OVER (partition by customer_id)::numeric,2) as stddev_delta
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,count_order
	   ,stddev_chek
	   ,stddev_delta
FROM level4)
SELECT *
FROM level5
WHERE stddev_delta > stddev_chek

-- 728. «Клієнт із прихованою інверсією тренду»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(corr(rn, sum_chek)::numeric,4) as corr_rn_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id order by order_date) as cumm_sum_chek
FROM level1
JOIN level2 USING (customer_id)
WHERE corr_rn_chek between - 0.05 AND 0.05 AND count_order >= 12),
level4 as(SELECT *
       ,LEAD(cumm_sum_chek) OVER (partition by customer_id order by order_date) as next_cumm_sum_chek
FROM level3),
level5 as(SELECT *
       ,next_cumm_sum_chek - cumm_sum_chek as delta
FROm level4),
level6 as(SELECT *
       ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
	   ,ROUND(STDDEV(delta) OVER (partition by customer_id)::numeric,2) as stddev_delta
FROM level5)
SELECT DISTINCT customer_id
       ,count_order
	   ,corr_rn_chek
	   ,stddev_chek
	   ,stddev_delta
FROM level6
WHERE stddev_chek > stddev_delta

-- 729. «Клієнт із порушенням балансу знаків»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,lag(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 'high'
	   when sum_chek < prev_chek THEN 'low'
	   when sum_chek = prev_chek THEN 'equal'
	   END as gradation
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE gradation = 'high') OVER (partition by customer_id) as count_order_high
	   ,COUNT(order_id) FILTER (WHERE gradation = 'low') OVER (partition by customer_id) as count_order_low
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,count_order
	   ,count_order_high
	   ,count_order_low
FROM level4),
level6 as(SELECT *
       ,count_order_high - count_order_low as diff
FROM level5)
SELECT *
FROM level6
WHERE diff >= 4

-- 730. «Клієнт із перевернутим екстремумом»

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
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,MIN(case when sum_chek = max_chek THEN rn END) OVER (partition by customer_id) as rn_max_chek
	   ,MIN(case when sum_chek = min_chek THEN rn END) OVER (partition by customer_id) as rn_min_chek
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,max_chek
	   ,min_chek
	   ,rn_max_chek
	   ,rn_min_chek
FROM level3),
level5 as(SELECT *
       ,rn_min_chek - rn_max_chek as diff_rn
FROM level4)
SELECT *
FROM level5
WHERE diff_rn >= 1

-- 731. «Клієнт із прихованою концентрацією ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
	   ,ROUND((count_order * 0.2)::numeric,0) as count_20_perc
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,case when rn_chek <= count_20_perc THEN 'top'
	   else 'other' END as gradation
FROM level2),
level4 as(SELECT *
       ,SUM(sum_chek) FILTER (WHERE gradation = 'top') OVER (partition by customer_id) as total_revenue_top_20_perc
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,count_order
	   ,total_revenue
	   ,count_20_perc
	   ,total_revenue_top_20_perc
FROM level4),
level6 as(SELECT *
       ,ROUND((total_revenue_top_20_perc / total_revenue)::numeric,4) as ratio
FROM level5)
SELECT *
FROM level6
WHERE ratio > 0.6

-- 732. «Клієнт із латентною домінантною фазою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek,1) OVER (partition by customer_id order by order_date) as next_1_chek
	   ,LEAD(sum_chek,2) OVER (partition by customer_id order by order_date) as next_2_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,sum_chek + next_1_chek + next_2_chek as sum_3_orders
FROM level2),
level4 as(SELECT *
       ,ROUND((sum_3_orders / total_revenue)::numeric,4) as ratio
FROM level3)
SELECT *
FROM level4
WHERE ratio >= 0.5

-- 733. «Клієнт із внутрішнім парадоксом середнього»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ntile(4) OVER (partition by customer_id order by order_date) as ntile 
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE ntile = 1) OVER (partition by customer_id)::numeric,2) as avg_chek_1
	   ,ROUND(AVG(sum_chek) FILTER (WHERE ntile = 2) OVER (partition by customer_id)::numeric,2) as avg_chek_2
	   ,ROUND(AVG(sum_chek) FILTER (WHERE ntile = 3) OVER (partition by customer_id)::numeric,2) as avg_chek_3
	   ,ROUND(AVG(sum_chek) FILTER (WHERE ntile = 4) OVER (partition by customer_id)::numeric,2) as avg_chek_4
FROM level2)
SELECT *
FROM level3
WHERE avg_chek > avg_chek_1 AND avg_chek > avg_chek_2 
AND avg_chek > avg_chek_3 AND avg_chek > avg_chek_4