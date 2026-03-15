-- 515. «Клієнт з ефектом фальшивого зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum(quantity) as sum_quantity
	   ,count(order_id) OVER (partition by customer_id) as count_order
	   ,count(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USINg (order_id)
GROUP BY customer_id, order_id, order_date),
level2 aS(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_prod
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level3 as(select *
from level1
JOIN level2 USING (customer_id, order_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,case when rn <= middle_point THen 'first'
	   when rn > middle_point then 'second'
	   END as halfs
FROM level3),
level5 as(SELECT customer_id
      ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	  ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
	  ,ROUND(AVG(count_unik_prod) FILTER (WHERE halfs = 'first')::numeric,2) as avg_count_unik_first
	  ,ROUND(AVG(count_unik_prod) FILTER (WHERE halfs = 'second')::numeric,2) as avg_count_unik_second
FROm level4
GROUP BY customer_id)
SELECT *
FROM level5
WHERE avg_quantity_second > avg_quantity_first AND avg_count_unik_second <= avg_count_unik_first

-- 516. «Клієнт з ефектом втраченого імпульсу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,MAX(case when sum_chek = max_chek THEN order_date END) OVER (partition by customer_id) as date_peak
FROm level2),
level4 as(SELECT *
       ,case when order_date < date_peak THEN 'before'
	   when order_date > date_peak THEN 'after'
	   when order_date = date_peak then 'peak'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,COUNT(order_id) FILTER (WHERE gradation = 'before') OVER (partition by customer_id) as count_order_before
	   ,COUNT(order_id) FILTER (WHERE gradation = 'after') OVER (partition by customer_id) as count_order_after
FROM level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'before')::numeric,2) as avg_chek_before
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'peak')::numeric,2) as avg_chek_peak
	   ,ROUND(AVG(sum_chek) FILTER (where gradation = 'after')::numeric,2) as avg_chek_after
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE gradation = 'before')::numeric,2) as std_dev_chek_before
FROM level5
WHERE count_order_before >= 2 AND count_order_after >= 2
GROUP BY customer_id),
level7 as(SELECT *
       ,case when avg_chek_peak >= avg_chek_before + (1.5 * std_dev_chek_before) THEN 'yes'
	   ELSE 'no' END as flag_peak_before
FROm level6)
SELECT *
FROm level7
WHERE flag_peak_before = 'yes' AND avg_chek_after < avg_chek_before

-- 517. «Клієнт із зсувом норми»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND((sum_chek - median_chek)::numeric,2) as deviation
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
	   ,ntile(3) OVER (partition by customer_id order by order_date) as ntile
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 8),
level4 as(SELECT *
       ,case when sum_chek >= median_chek + (2 * std_dev_chek) THEN 1 ELSE 0 END as flag_diff
FROM level3),
level5 as(SELECT *
       ,SUM(flag_diff) OVER (partition by customer_id) as sum_flag_diff
FROM level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(deviation) FILTER (WHERE ntile = 1)::numeric,2) as avg_dev_ntile_1
	   ,ROUND(AVG(deviation) FILTER (WHERE ntile = 3)::numeric,2) as avg_dev_ntile_3
FROM level5
WHERE sum_flag_diff = 0
GROUP BY customer_id)
SELECT *
FROM level6
WHERE avg_dev_ntile_1 < 0 AND avg_dev_ntile_3 > 0 

-- 518. «Клієнт з розірваною стабільністю»

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
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::Numeric,2) as avg_chek
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,sum_chek - avg_chek as deviation
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THen 'second'
	   END as halfs
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(STDDEV(deviation) FILTER (WHERE halfs = 'first')::numeric,2) as std_dev_deviation_first
	   ,ROUND(STDDEV(deviation) FILTER (WHERE halfs = 'second')::numeric,2) as std_dev_deviation_second
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
FROM level4)
SELECT *
FROm level5
WHERE diff_chek <= 0.05 AND std_dev_deviation_second >= 2 * std_dev_deviation_first

-- 519. «Клієнт з пам’яттю попереднього замовлення»

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
FROm level1),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
FROm level2),
level4 as(SELECT customer_id
       ,ROUND(corr(sum_chek, prev_chek)::numeric,4) as corr_chek_and_prev
FROm level3
GROUP By customer_id),
level5 as(SELECT *
       ,ROUND(STDDEV(delta_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
FROM level3
JOIN level4 USING (customer_id)),
level6 as(SELECT DISTINCT customer_id
       ,count_order
	   ,corr_chek_and_prev
	   ,std_dev_chek
	   ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by std_dev_chek) FROM level5) as global_median_stddev
FROM level5)
SELECT *
FROM level6
WHERE count_order >= 8 AND corr_chek_and_prev >= 0.6 
AND std_dev_chek > global_median_stddev

-- 520. «Клієнт з ефектом компенсації»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,sum_chek - prev_chek as delta_chek
FROM level2),
level4 as(SELECT *
       ,LAG(delta_chek) OVER (partition by customer_id order by order_date) as prev_delta_chek
FROM level3),
level5 as(SELECT customer_id
       ,ROUND(corr(delta_chek, prev_delta_chek)::numeric,4) as corr_deltas
FROm level4
GROUP BY customer_id)
SELECT *
FROM level4
JOIN level5 USING (customer_id)
WHERE count_order >= 9 AND corr_deltas <= -0.5 
AND prev_delta_chek is not null),
block2 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order_customer
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
WHERE count_order_customer >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(order_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(order_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_first - avg_chek_second) / avg_chek_first)::numeric,2) as diff_chek
FROm level3)
SELECT *
FROM level4
WHERE diff_chek <= 0.05)
SELECT *
FROM block1
JOIN block2 USING (customer_id)

-- 521. «Клієнт, який втомлюється»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(corr(sum_chek, rn)::numeric,4) as corr_chek_rn
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,case when sum_chek >= avg_chek + (2 * std_dev_chek) THEN 1 ELSE 0 END as flag_deviation
FROM level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,SUM(flag_deviation) OVER (partition by customer_id) as sum_flag_deviation
FROm level4),
level6 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,std_dev_chek
	   ,corr_chek_rn
	   ,sum_flag_deviation
	   ,(SELECt percentile_cont(0.5) WITHIN GROUP (order by std_dev_chek) FROM level5) as global_median_stddev
FROM level5
WHERE sum_flag_deviation = 0 AND corr_chek_rn <= - 0.6)
SELECT *
FROM level6
WHERE std_dev_chek < global_median_stddev AND count_order >= 8

-- 522. «Клієнт з фальшивим ростом чеку»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,count(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(corr(sum_chek, sum_quantity)::numeric,2) as corr_chek_qnt
	   ,ROUND(corr(sum_chek, avg_price)::numeric,2) as corr_chek_price
FROm level1
GROUP BY customer_id),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
JOIn level2 USING (customer_id)
WHERE count_order >= 6 AND corr_chek_qnt >= 0.7 AND corr_chek_price <= 0.2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
FROM level3
GROUP By customer_id)
SELECT *
FROM level4
WHERE avg_chek_second > avg_chek_first