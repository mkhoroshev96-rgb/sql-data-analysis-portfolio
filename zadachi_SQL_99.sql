-- 639. «Клієнт з ефектом зламаної квантілі»

WITH level1 as(SELECT customer_id
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
FROm level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,percentile_cont(0.75) WITHIN GROUP (order by sum_chek) as percentile_75_chek
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT customer_id
       ,AVG(median_chek) FILTER (WHERE halfs = 'first') as median_chek_first
	   ,AVG(percentile_75_chek) FILTER (WHERE halfs = 'second') as perc_75_chek_second
FROm level2
JOIN level3 USING (customer_id, halfs)
GROUP BY customer_id)
SELECT *
FROm level4
WHERE median_chek_first > perc_75_chek_second

-- 640. «Клієнт з ефектом краху еліти»

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
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, halfs order by sum_chek DESC) as rn_halfs
FROm level2),
level4 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as count_order_second
	   ,COUNT(order_id) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) / 2 as middle_point_second
FROm level3
WHERE (halfs = 'first' AND rn_halfs <= 3) or (halfs = 'second' AND rn_halfs >= 1)),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek DESC) as rn_total
FROm level4),
level6 as(SELECT *
       ,case when rn_total >=  middle_point_second THEN 1 ELSE 0 END as flag_rn_total
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order_first
FROm level5
WHERE halfs = 'first'),
level7 as(SELECT *
       ,SUM(flag_rn_total) OVER (partition by customer_id) as sum_flag_rn_total
FROM level6)
SELECT *
FROm level7
WHERE count_order_first = sum_flag_rn_total

-- 641. «Клієнт з ефектом прихованого порядкового парадоксу» (задача рівня сеньйор - ВПЕРШЕ в мене тут в SQL)

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
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
FROm level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
       ,AVG(median_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as median_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as avg_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as avg_chek_second
FROm level2
JOIN level3 USING (customer_id, halfs)),
level5 as(SELECT *
       ,case when sum_chek < median_chek_first THEN 1 ELSE 0 END as flags
	   ,count(order_id) OVER (partition by customer_id) as count_order_second
FROm level4
WHERE halfs = 'second' AND avg_chek_second > avg_chek_first),
level6 as(SELECT *
       ,SUM(flags) OVER (partition by customer_id) as sum_flags
FROM level5),
level7 as(SELECT *
       ,sum_flags::numeric / count_order_second::numeric as ratio
FROm level6)
SELECT *
FROm level7
WHERE ratio > 0.5

-- 642. «Клієнт з ефектом структурного перекосу ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
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
WHERE count_order >= 12),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, halfs order by sum_chek DESC) as rn_chek_halfs
FROm level2),
level4 as(SELECT customer_id
       ,SUM(sum_chek) FILTER (WHERE halfs = 'first' AND rn_chek_halfs <= 3) as sum_chek_top_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'first') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second' AND rn_chek_halfs <= 3) as sum_chek_top_second
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second') as total_revenue_second
FROm level3
GROUP By customer_id),
level5 as(SELECT *
       ,sum_chek_top_first / total_revenue_first as ratio_first
	   ,sum_chek_top_second / total_revenue_second as ratio_second
FROm level4)
SELECT *
FROM level5
WHERE ratio_second > 0.5 AND ratio_first < 0.4

-- 643. «Клієнт з ефектом прихованої асиметрії масштабу»

WITH level1 as (SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEn 'second'
	   END as halfs
FROm level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,AVG(sum_chek) as avg_chek
FROM level2
GROUP BY customer_id, halfs),
level4 as(SELECT customer_id
       ,AVG(median_chek) FILTER (WHERE halfs = 'first') as median_chek_first
	   ,AVG(median_chek) FILTER (WHERE halfs = 'second') as median_chek_second
	   ,AVG(avg_chek) FILTER (WHERE halfs = 'first') as avg_chek_first
	   ,AVG(avg_chek) FILTER (WHERE halfs = 'second') as avg_chek_second
FROM level2
JOIN level3 USING (customer_id, halfs)
GROUP By customer_id)
SELECT *
FROM level4
WHERE avg_chek_second > avg_chek_first AND median_chek_second < median_chek_first

-- 644. «Клієнт з ефектом прихованого зсуву вагового центру»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
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
	   ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,AVG(rn_chek) FILTER (WHERE halfs = 'first') as avg_rn_chek_first
	   ,AVG(rn_chek) FILTER (WHERE halfs = 'second') as avg_rn_chek_second
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'first') as avg_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'second') as avg_chek_second
FROm level2
GROUP BY customer_id)
SELECt *
FROm level3
WHERE avg_rn_chek_second > avg_rn_chek_first AND avg_chek_second > avg_chek_first

-- 645. «Клієнт з ефектом прихованої квантільної інверсії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
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
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.25) WITHIN GROUP (order by sum_chek) as perc_25
	   ,percentile_cont(0.75) WITHIN GROUP (order by sum_chek) as perc_75
FROM level2
GROUP BY customer_id, halfs),
level4 as(SELECT customer_id
       ,AVG(perc_75) FILTER (WHERE halfs = 'first') as perc_75_first
	   ,AVG(perc_25) FILTER (WHERE halfs = 'second') as perc_25_second
FROM level2
JOIN level3 USING (customer_id, halfs)
GROUP By customer_id)
SELECT *
FROM level4
WHERE perc_25_second > perc_75_first

-- 646. «Клієнт з ефектом прихованої кумулятивної інверсії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
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
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id, halfs order by order_date) as cumm_sum_chek_halfs
	   ,ROW_NUMBER () OVER (partition by customer_id, halfs order by order_date) as rn_halfs
	   ,COUNT(order_id) OVER (partition by customer_id, halfs) as count_order_halfs
	   ,COUNT(order_id) OVER (partition by customer_id, halfs) / 2 as middle_point_halfs
FROm level2),
level4 as(SELECT *
       ,SUM(cumm_sum_chek_halfs) FILTER (where halfs = 'first') OVER (partition by customer_id) as cumm_revenue_first
	   ,SUM(cumm_sum_chek_halfs) FILTER (where halfs = 'second') OVER (partition by customer_id) as cumm_revenue_second
FROm level3
WHERE (rn_halfs <= middle_point_halfs))
SELECT *
FROm level4
WHERE cumm_revenue_second > cumm_revenue_first