-- 632. «Клієнт з ефектом втраченої чутливості до знижки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,discount
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,order_date
       ,COUNT (order_id) OVER (partition by customer_id) as count_order
	   ,COUNT (order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
JOIN level2 USING (customer_id, order_id)
WHERE count_order >= 8),
level4 as(SELECT customer_id
       ,halfs
	   ,corr(discount, quantity) as corr_disc_qnt
FROm level3
GROUP BY customer_id, halfs),
level5 as(SELECT customer_id
       ,ROUND(AVG(corr_disc_qnt) FILTER (WHERE halfs = 'first')::numeric,4) as corr_disc_qnt_first
	   ,ROUND(AVG(corr_disc_qnt) FILTER (WHERE halfs = 'second')::numeric,4) as corr_disc_qnt_second
FROm level3
JOIN level4 USING (customer_id, halfs)
GROUP By customer_id)
SELECT *
FROm level5
WHERE corr_disc_qnt_first is not null AND corr_disc_qnt_second is not null
AND corr_disc_qnt_first > 0.3 AND corr_disc_qnt_second <= 0

-- 633. «Клієнт з ефектом інерційного перекосу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN group (order by sum_chek) as median_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek <= median_chek THEN 'low'
	   END as gradation
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation
FROm level3),
level5 as(SELECT *
       ,count_order - 1 as real_count
	   ,case when prev_gradation = 'low' AND gradation = 'high' THEN 1 ELSE 0 END as low_high
	   ,case when prev_gradation = 'high' AND gradation = 'low' THEN 1 ELSE 0 END as high_low
FROM level4
WHERE prev_gradation is not null),
level6 as(SELECT *
       ,SUM(low_high) OVER (partition by customer_id) as sum_low_high
	   ,SUM(high_low) OVER (partition by customer_id) as sum_high_low
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_low_high::numeric / real_count::numeric),4) as ratio_low_high
	   ,ROUND((sum_high_low::numeric / real_count::numeric),4) as ratio_high_low
FROm level6),
level8 as(SELECT *
       ,ABS(ratio_low_high - ratio_high_low) as abs_diff_ratio
FROm level7)
SELECT *
FROM level8
WHERE abs_diff_ratio >= 0.4

-- 634. «Клієнт з ефектом внутрішнього циклу»

WITh level1 as(SELECT customer_id
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
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek <= median_chek THEN 'low'
	   END as gradation
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 9),
level4 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation
	   ,LEAD(gradation) OVER (partition by customer_id order by order_date) as next_gradation
FROm level3),
level5 as (SELECT *
       ,case when (prev_gradation = 'low' AND gradation = 'high' AND next_gradation = 'low')
	   OR (prev_gradation = 'high' AND gradation = 'low' AND next_gradation = 'high') THEN 1
	   ELSE 0 END as flag_triplet
FROm level4
WHERE prev_gradation is not null AND next_gradation is not null),
level6 as(SELECT *
       ,count_order - 2 as real_count
	   ,SUM(flag_triplet) OVER (partition by customer_id) as sum_flag_triplet
FROM level5),
level7 as(SELECT DISTINCT customer_id
	   ,real_count
	   ,sum_flag_triplet
	   ,ROUND((sum_flag_triplet::numeric / real_count::numeric),4) as ratio_triplet
FROM level6)
SELECT *
FROm level7
WHERE ratio_triplet >= 0.3

-- 635. «Клієнт з ефектом фрагментації стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek 
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek <= median_chek THEN 'low'
	   END as gradation
FROm level1
JOIN level2 USING (customer_id)),
level4 as(SELECT *
       ,LAG(gradation) OVER (partition by customer_id order by order_date) as prev_gradation 
FROm level3),
level5 as(SELECT *
       ,case when gradation = prev_gradation THEN 0 ELSE 1 END as flag_gradation
FROM level4),
level6 as(SELECT *
       ,SUM(flag_gradation) OVER (partition by customer_id order by order_date) as series_id
FROm level5),
level7 as(SELECT customer_id
       ,series_id
	   ,COUNT(series_id) as count_series
FROm level6
GROUP By customer_id, series_id),
level8 as(SELECT *
       ,MAX(count_series) OVER (partition by customer_id) as max_count_series
FROm level6
JOIn level7 USING (customer_id, series_id)),
level9 as(SELECT DISTINCT customer_id
       ,max_count_series
	   ,count_order
	   ,ROUND((max_count_series::numeric / count_order::numeric),4) as ratio_streak
FROm level8)
SELECT *
FROM level9
WHERE ratio_streak <= 0.4

-- 636. «Клієнт з ефектом прихованого структурного зламу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) /2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,AVG(sum_chek) FILTER (WHERE halfs = 'first') as avg_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'second') as avg_chek_second
	   ,STDDEV(sum_chek) FILTER (WHERE halfs = 'first') as stddev_chek_first
	   ,STDDEV(sum_chek) FILTER (WHERE halfs = 'second') as stddev_chek_second
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND((stddev_chek_first / avg_chek_first),4) as cv_first
	   ,ROUND((stddev_chek_second / avg_chek_second),4) as cv_second
FROM level3)
SELECT *
FROM level4
WHERE cv_second >= 2 * cv_first

-- 637. «Клієнт з ефектом прихованої інверсії порядку»

WITH level1 as (SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
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
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,halfs
	   ,corr(rn, sum_chek) as corr_rn_chek
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT customer_id
       ,ROUND(AVG(corr_rn_chek) FILTER (WHERE halfs = 'first')::numeric,4) as corr_rn_chek_first
	   ,ROUND(AVG(corr_rn_chek) FILTER (WHERE halfs = 'second')::numeric,4) as corr_rn_chek_second
FROm level2
JOIN level3 USING (customer_id, halfs)
GROUP By customer_id)
SELECT *
FROm level4
WHERE corr_rn_chek_first > 0.4 AND corr_rn_chek_second < -0.4

-- 638. «Клієнт з ефектом структурної диверсифікації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,(p.unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
JOIn level2 USING (customer_id, order_id)),
level4 as(SELECT customer_id
       ,category_id
       ,SUM(chek) FILTER (WHERE halfs = 'first') as sum_chek_first
	   ,SUM(chek) FILTER (WHERE halfs = 'second') as sum_chek_second
FROm level3
GROUP BY customer_id, category_id),
level5 as(SELECT *
       ,SUM(sum_chek_first) OVER (partition by customer_id) as total_chek_first
	   ,SUM(sum_chek_second) OVER (partition by customer_id) as total_chek_second
FROm level4),
level6 as(SELECT *
       ,sum_chek_first / total_chek_first as p_i_first
	   ,sum_chek_second / total_chek_second as p_i_second
FROm level5),
level7 as(SELECT customer_id
       ,-SUM(p_i_first * LN(p_i_first)) FILTER (WHERE p_i_first  IS NOT NULL) as H_first
	   ,-SUM(p_i_second * LN(p_i_second)) FILTER (WHERE p_i_second IS NOT NULL) as H_second
FROm level6
GROUP By customer_id)
SELECT *
FROm level7
WHERE H_second >= H_first + 0.5
