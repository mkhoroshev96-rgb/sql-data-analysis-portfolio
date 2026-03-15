-- 676. «Клієнт з ефектом перевернутої стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,stddev_chek / avg_chek as cv
FROM level2)
SELECT * 
FROM level3
WHERE cv <= 0.15

-- 677. «Клієнт з ефектом прихованої асиметрії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
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
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP By customer_id, halfs),
level4 as(SELECT DISTINCT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id)::numeric,2) as avg_chek_second
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id)::numeric,2) as median_chek_first
	   ,ROUND(AVG(median_chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id)::numeric,2) as median_chek_second
FROm level2
JOIN level3 USING (customer_id, halfs)),
level5 as(SELECT *
       ,ROUND((ABS(avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
	   ,ROUND((ABS(median_chek_second - median_chek_first)/median_chek_first)::numeric,2) as diff_median_chek
FROm level4)
SELECT *
FROm level5
WHERE diff_chek <= 0.05 AND diff_median_chek >= 0.25

-- 678. «Клієнт із ефектом латентної концентрації»

WITH block1 as(WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,category_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
JOIN level2 USING (customer_id, order_id, order_date)
WHERE count_order >= 12),
level4 as(SELECT DISTINCT customer_id
       ,category_id
	   ,ROUND(SUM(chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id, category_id)::numeric,2) as sum_chek_category_first
	   ,ROUND(SUM(chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id, category_id)::numeric,2) as sum_chek_category_second
	   ,SUM(chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as total_revenue_first
	   ,SUM(chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as total_revenue_second
FROM level3),
level5 as(SELECT *
	   ,ROUND((sum_chek_category_first / total_revenue_first)::numeric,4) as ratio_first
	   ,ROUND((sum_chek_category_second / total_revenue_second)::numeric,4) as ratio_second
FROm level4),
level6 as(SELECT *
       ,MAX(ratio_first) OVER (partition by customer_id) as max_ratio_first
	   ,MAX(ratio_second) OVER (partition by customer_id) as max_ratio_second
FROm level5)
SELECT *
FROm level6
WHERE max_ratio_first <= 0.4 AND max_ratio_second >= 0.7),
block2 as(WITH level1 as(SELECT customer_id
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
FROM level1
WHERE count_order >= 12),
level3 as(SELECT customer_id
       ,AVG(sum_chek) FILTER (WHERE halfs = 'first') as avg_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'second') as avg_chek_second
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_avg_chek
FROM level3)
SELECT *
FROm level4
WHERE diff_avg_chek <= 0.1)
SELECT *
FROM block1
JOIN block2 USING (customer_id)

-- 679. «Клієнт з ефектом вибухового піку»

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
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1
WHERE count_order >= 8),
level3 as(SELECT DISTINCT customer_id
       ,max_chek / avg_chek as ratio
FROm level2)
SELECT *
FROm level3
WHERE ratio >= 3

-- 680. «Клієнт з ефектом прихованого обвалу»

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
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT DISTINCT customer_id
       ,max_chek / avg_chek as ratio_max
	   ,min_chek / avg_chek as ratio_min
FROm level2)
SELECT *
FROm level3
WHERE ratio_max < 2 AND ratio_min <= 0.25

-- 681. «Клієнт із прихованою залежністю від знижки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,AVG(discount) as avg_discount
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,corr(sum_chek, avg_discount) as corr_chek_discount
FROm level1
WHERE count_order >= 12
GROUP BY customer_id)
SELECT *
FROm level2
WHERE corr_chek_discount <= -0.6

-- 682. «Клієнт із псевдо-проривом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek DESC) as rn_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn_date
FROM level2),
level4 as(SELECT *
       ,MAX(case when rn_chek = 2 THEN order_date END) OVER (partition by customer_id) as date_second_max_chek
	   ,MAX(case when rn_chek = 2 THEN sum_chek END) OVER (partition by customer_id) as second_max_chek
FROm level3),
level5 as(SELECT *
       ,case when order_date < date_second_max_chek THEN '1_before'
	   when order_date > date_second_max_chek THEN '2_after'
	   when order_date = date_second_max_chek THEN 'equal'
	   END as gradation
FROm level4),
level6 as(SELECT *
       ,case when sum_chek > second_max_chek THEN 1 ELSE 0 END as flag_chek
FROm level5
WHERE gradation = '2_after'),
level7 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level6)
SELECT *
FROm level7
WHERE sum_flag_chek = 0

-- 683. «Клієнт із ефектом внутрішньої нестабільності при зростанні»

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
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
	   ,stddev(sum_chek) OVER (partition by customer_id) as stddev_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,stddev_chek / avg_chek as cv
FROm level2),
level4 as(SELECT customer_id
       ,ROUND(corr(rn, sum_chek)::numeric,4) as corr_rn_chek
FROm level3
GROUP By customer_id)
SELECT *
FROm level3
JOIN level4 USING (customer_id)
WHERE corr_rn_chek >= 0.6 AND cv >= 0.4

-- 684.«Клієнт із ефектом ілюзії диверсифікації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,p.product_id
	   ,(p.unit_price * quantity * (1-discount)) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)),
level2 as(SELECT customer_id
       ,COUNT(DISTINCT product_id) as count_unik_product
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_unik_product >= 20),
level4 as(SELECT DISTINCT customer_id
       ,product_id
	   ,ROUND(SUM(chek) OVER (partition by customer_id, product_id)::numeric,2) as sum_chek_customer
	   ,ROUND(SUM(chek) OVER (partition by customer_id)::numeric,2) as total_revenue_customer
FROM level3
ORDER BY customer_id),
level5 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by sum_chek_customer DESC) as top_chek
FROM level4),
level6 as(SELECT *
       ,SUM(sum_chek_customer) FILTER (WHERE top_chek <= 3) OVER (partition by customer_id) as sum_chek_top_3
FROm level5
WHERE top_chek <= 3),
level7 as(SELECT *
       ,ROUND((sum_chek_top_3 / total_revenue_customer)::numeric,4) as ratio
FROM level6)
SELECT *
FROm level7
WHERE ratio >= 0.7