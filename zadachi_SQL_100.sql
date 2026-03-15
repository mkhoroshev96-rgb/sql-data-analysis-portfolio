-- 647. «Ефект територіальної концентрації обороту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ship_country
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ship_country
	   ,SUM(sum_chek) OVER (partition by customer_id) as chek_country
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,ship_country
	   ,chek_country
FROm level2),
level4 as(SELECT *
       ,ROW_NUMBER () OVER ( order by chek_country DESC) as rn_chek
FROm level3)
SELECT *
FROm level4
WHERE rn_chek <= 3

-- 648. Подвійна квантільна інверсія з компенсаційним перекосом

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
WHERE count_order >= 14),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.25) WITHIN GROUP (order by sum_chek) as perc_25
	   ,percentile_cont(0.75) WITHIN GROUP (order by sum_chek) as perc_75
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level2
GROUP By customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id, halfs)),
level5 as(SELECT customer_id
       ,AVG(perc_25) FILTER (WHERE halfs = 'second') as perc_25_second
	   ,AVG(perc_75) FILTER (WHERE halfs = 'first') as perc_75_first
	   ,AVG(median_chek) FILTER (WHERE halfs = 'first') as median_chek_first
	   ,AVG(median_chek) FILTER (WHERE halfs = 'second') as median_chek_second
FROM level4
GROUP By customer_id),
level6 as(SELECT *
       ,ABS((median_chek_second - median_chek_first) / median_chek_first) as diff_medians
FROm level5
WHERE perc_25_second > perc_75_first)
SELECT *
FROM level6
WHERE diff_medians <= 0.05

-- 649. Кумулятивна рангово-квантільна інверсія

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
FROm level1
WHERE count_order >= 15),
level3 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,percentile_cont(0.75) WITHIn GROUP (order by sum_chek) as perc_75
FROm level2
GROUP BY customer_id, halfs),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id, halfs)),
level5 as(SELECT *
       ,AVG(median_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as median_chek_second
	   ,AVG(perc_75) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as perc_75_first
FROM level4),
level6 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
	   ,(count_order * 0.6)::integer as perc_60_order_last
	   ,(count_order * 0.4)::integer as perc_40_order_first
FROm level5
WHERE median_chek_second > perc_75_first),
level7 as(SELECT *
       ,SUM(sum_chek) FILTER (WHERE rn <= perc_40_order_first) OVER (partition by customer_id order by order_date) as cumm_sum_perc_40_first
	   ,SUM(sum_chek) FILTER (WHERE rn_invert <= perc_60_order_last) OVER (partition by customer_id order by order_date DESC) as cumm_sum_perc_60_last
FROm level6),
level8 as(SELECT customer_id
       ,MAX(cumm_sum_perc_40_first) as max_perc_40_first
	   ,MAX(cumm_sum_perc_60_last)  as max_perc_60_last
FROm level7
GROUP By customer_id)
SELECT *
FROM level8
WHERE max_perc_40_first > max_perc_60_last

-- 650. Квантільно-рангова симетрична інверсія

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id)::numeric,2) as avg_chek_second
FROm level2),
level4 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,avg_chek_first
	   ,avg_chek_second
FROm level3),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (order by avg_chek_first DESC) as rn_first
	   ,ROW_NUMBER () OVER (order by avg_chek_second) as rn_second
	   ,ROW_NUMBER () OVER (order by avg_chek DESC) as total_rn
	   ,COUNT(customer_id) OVER () as total_customer
FROm level4),
level6 as(SELECT *
       ,ROUND((total_customer * 0.3)::numeric,0) as perc_30_customer
	   ,ROUND((total_customer * 0.4)::numeric,0) as perc_40_customer
FROm level5)
SELECT *
FROM level6
WHERE rn_first <= perc_30_customer AND rn_second <= perc_30_customer AND total_rn <= perc_40_customer

-- 651. Ефект кумулятивного зсуву центру мас

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,count(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,AVG(sum_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as avg_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as avg_chek_second
FROM level2),
level4 as(SELECT *
       ,ROUND((count_order * 0.5)::numeric,0) as perc_50_count
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROm level3
WHERE avg_chek_second > avg_chek_first),
level5 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as perc_50_sum_chek
FROM level4
WHERE rn <= perc_50_count),
level6 as(SELECT *
       ,perc_50_sum_chek / total_revenue as ratio
FROm level5)
SELECT *
FROm level6
WHERE ratio >= 0.7

-- 652. Парадокс спадного обсягу при зростанні середнього чека

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'first') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second') as total_revenue_second
FROm level2
GROUP By customer_id)
SELECT *
FROm level3
WHERE avg_quantity_second < avg_quantity_first AND avg_chek_second > avg_chek_first
AND total_revenue_second >= total_revenue_first

-- 653. топ-3 клієнти за сумарним обсягом куплених одиниць

WITh level1 as(select customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
from orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id) as total_revenue
FROm level1)
SELECT DISTINCT customer_id
       ,total_revenue
FROm level2
ORDER BY total_revenue DESC
LIMIT 3