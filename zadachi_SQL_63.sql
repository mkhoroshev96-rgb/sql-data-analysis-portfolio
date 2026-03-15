-- 404. «Клієнт із нестабільною цінністю замовлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
FROM level1),
level3 as(SELECT *
       ,ROUND((std_dev_chek/avg_chek)::numeric,2) as cv
FROm level2),
level4 as(SELECT DISTINCT customer_id
	   ,count_order
	   ,avg_chek
	   ,global_avg_chek
	   ,std_dev_chek
	   ,cv
FROM level3),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by cv) FROM level4) as global_median_cv
FROM level4)
SELECT *
FROm level5
WHERE count_order >= 6 AND diff_chek <= 0.1 AND cv > global_median_cv

-- 405. «Клієнт з ефектом зниклої вигоди»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
	   ,ROUND((sum_chek / 10)::numeric,0) as sum_chek_div_10
FROM level1),
level3 as(SELECT *
       ,sum_chek_div_10 * 10 as sum_chek_rounded_10
	   ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_avg_chek
FROM level2),
level4 as(SELECT *
       ,ROUND(ABS((sum_chek - sum_chek_rounded_10::numeric) / sum_chek_rounded_10::numeric),2) as diff_sum_chek
FROM level3),
level5 as(SELECT *
       ,case when diff_sum_chek <= 0.01 then 1 ELSE 0 END as flag_diff_sum_chek
FROM level4),
level6 as(SELECT *
       ,SUM(flag_diff_sum_chek) OVER (partition by customer_id) as sum_flag_diff_sum_chek
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_diff_sum_chek::numeric / count_order::numeric),2) as ratio_sum_chek
FROM level6
WHERE count_order >= 8),
level8 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,global_avg_chek
	   ,diff_avg_chek
	   ,sum_flag_diff_sum_chek
	   ,ratio_sum_chek
FROM level7),
level9 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by ratio_sum_chek) FROM level8) as median_round_rate
FROM level8)
SELECT *
FROm level9
WHERE diff_avg_chek <= 0.15 AND ratio_sum_chek > median_round_rate

-- 406. «Клієнт, який здається стабільним»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(sum_chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,ROUND(ABS((sum_chek - median_chek) / median_chek)::numeric,2) as diff_sum_chek
	   ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_avg_chek
FROM level3),
level5 as(SELECT *
       ,case when diff_sum_chek <= 0.1 THEN 1 ELSE 0 END as flag_diff_sum_chek
FROm level4
WHERE count_order >= 6 AND diff_avg_chek <= 0.1),
level6 as(SELECT *
       ,SUM(flag_diff_sum_chek) OVER (partition by customer_id) as sum_flag_diff
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_diff::numeric / count_order::numeric),2) as ratio
FROM level6)
SELECT *
FROm level7
WHERE ratio < 0.2

-- 407. «Клієнт із прихованим перекосом асортименту»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(DISTINCT product_id) as count_unik_prod
FROM level1
GROUP By customer_id, order_id),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / count_unik_prod::numeric),2) as depth_ratio
FROM level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT DISTINCT customer_id,order_id
	   ,sum_quantity
	   ,count_unik_prod
	   ,depth_ratio
FROM level3),
level5 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
	   ,percentile_cont(0.5) WITHIN GROUP (order by depth_ratio) as median_depth_ratio
FROM level4
GROUP By customer_id),
level6 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) FROM level4) as global_median_quantity
FROM level4
JOIN level5 USING (customer_id)),
level7 as(SELECT *
       ,ROUND(ABS((median_quantity - global_median_quantity) / global_median_quantity)::numeric,2) as diff_quantity
FROm level6
WHERE count_order >= 6),
level8 as(SELECT DISTINCT customer_id
       ,median_quantity
	   ,median_depth_ratio
	   ,count_order
	   ,global_median_quantity
	   ,diff_quantity
FROM level7),
level9 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by median_depth_ratio) FROM level8) as baseline_depth_ratio
FROM level8)
SELECT *
FROM level9
WHERE diff_quantity <= 0.1 AND median_depth_ratio > baseline_depth_ratio

-- 408. «Клієнт з ілюзією покращення»

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
FROm level1),
level3 as(SELECT *
       ,ROUND(((sum_chek - prev_chek) / prev_chek)::numeric,2) as delta
FROm level2
WHERE prev_chek is not null),
level4 as(SELECT customer_id
       ,ROUND(AVG(delta)::numeric,2) as avg_delta
	   ,percentile_cont(0.5) WITHIN GROUP (order by delta) as median_delta
FROM level3
GROUP By customer_id)
SELECT *
FROm level3
JOIN level4 USING (customer_id)
WHERE count_order >= 6 AND avg_delta > 0 and median_delta < 0

-- 409. «Клієнт із пам’яттю останнього замовлення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta
	   ,count_order - 1 as real_count_order
FROM level2
WHERE prev_chek is not null AND count_order >= 7),
level4 as(SELECT *
       ,case when delta > 0 Then 'plus'
	   when delta < 0 then 'minus'
	   END as gradation
FROM level3),
level5 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE gradation = 'plus') as count_plus
	   ,COUNT(order_id) FILTER (WHERE gradation = 'minus') as count_minus
FROm level4
GROUP BY customer_id)
SELECT *
       ,ROUND((count_plus::numeric / real_count_order::numeric),2) as diff_plus
	   ,ROUND((count_minus::numeric / real_count_order::numeric),2) as diff_minus
FROM level4
JOIN level5 USING (customer_id)