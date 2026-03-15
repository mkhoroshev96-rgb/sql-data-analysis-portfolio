-- 817.«Індекс прихованої залежності від одного дня»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,EXTRACT(dow from order_date) as dow_day
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,sum(sum_chek) OVER (partition by customer_id, dow_day) as sum_chek_per_dow_day
FROM level1),
level3 as(SELECT DISTINCT customer_id
       ,dow_day
	   ,sum_chek_per_dow_day
	   ,total_revenue
FROM level2),
level4 as(SELECT customer_id
       ,count(distinct dow_day) as count_unik_dow_day
FROM level3
GROUP By customer_id),
level5 as(SELECT *
       ,MAX(sum_chek_per_dow_day) OVER (partition by customer_id) as max_chek
FROm level3
JOIN level4 USING (customer_id)
WHERE count_unik_dow_day >= 3),
level6 as(SELECT *
       ,max_chek / total_revenue as ratio
FROM level5)
SELECT DISTINCT customer_id
       ,ratio
FROM level6
ORDER BY ratio DESC

-- 818. «Невидимий рекорд»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level2),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3)
SELECT *
FROm level4
WHERE sum_chek = 0

-- 819. «Ілюзія постійності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date), 
level2 as(SELECT customer_id
       ,avg(sum_chek) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP By customer_id)
SELECT *
FROm level2
WHERE median_chek > avg_chek

-- 820. «Зламаний тренд клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,FIRST_VALUE(sum_chek) OVER (partition by customer_id order by order_date) as first_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,FIRST_VALUE(sum_chek) OVER (partition by customer_id order by order_date DESC) as last_chek
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROm level1),
level3 as(SELECT *
       ,case when sum_chek = first_chek AND rn = 1 THEN 'first'
	   when sum_chek = last_chek AND rn_invert = 1 THEN 'last'
	   else 'other' END as gradation
FROm level2),
level4 as(SELECT *
       ,SUM(sum_chek) FILTER (where gradation = 'other') OVER (partition by customer_id) as sum_chek_other
FROm level3)
SELECT DISTINCT customer_id
       ,first_chek
	   ,last_chek
	   ,sum_chek_other
FROM level4
WHERE first_chek > last_chek AND sum_chek_other > first_chek

-- 821. «Клієнт-дзеркало»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level2),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,sum_flag_chek
	   ,count_order
	   ,sum_flag_chek::numeric / count_order::numeric as ratio
FROM level4)
SELECT *
FROM level5
WHERE ratio = 0.5

-- 822. «Зниклий ордер»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::Numeric,2) as avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROm level1
WHERE count_order >= 2),
level3 as(SELECT *
       ,ROUND((total_revenue - sum_chek) / (count_order - 1)::numeric,2) as avg_chek_ohne_order
FROM level2)
SELECT *
FROM level3
WHERE avg_chek = avg_chek_ohne_order

-- 823. «Ордер перелому»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id order by order_date) as cumm_sum_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROm level1),
level3 as(SELECT *
       ,cumm_sum_chek / total_revenue as ratio
FROm level2),
level4 as(SELECT *
       ,MIN(case when ratio > 0.5 THEN ratio END) OVER (partition by customer_id) as first_ratio_high_50
FROM level3)
SELECT *
FROm level4
WHERE ratio = first_ratio_high_50 AND min_chek = sum_chek

-- 824. «Клієнт без центру»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by sum_chek DESC) as next_chek
	   ,LAG(sum_chek) OVER (partition by customer_id order by sum_chek DESC) as prev_chek
FROm level2),
level4 as(SELECT *
       ,ABS(sum_chek - next_chek) / sum_chek as diff_chek_next
	   ,ABS(sum_chek - prev_chek) / sum_chek as diff_chek_prev
FROm level3),
level5 as(SELECT *
       ,case when diff_chek_next <= 0.05 OR diff_chek_prev <= 0.05 THEN 1 ELSE 0 END as flag_chek
FROm level4),
level6 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROm level5)
SELECT *
FROm level6
WHERE sum_flag_chek = count_order

-- 825. «Перевернутий центр ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,AVG(sum_chek) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,case when sum_chek > median_chek THEN 'high'
	   when sum_chek < median_chek THEN 'low'
	   END as gradation
FROm level1
JOIN level2 USING (customer_id)
WHERE median_chek > avg_chek),
level4 as(SELECT customer_id
       ,SUM(sum_chek) FILTER (WHERE gradation = 'high') as sum_chek_high_median
	   ,SUM(sum_chek) FILTER (WHERE gradation = 'low') as sum_chek_low_median
FROm level3
GROUP By customer_id)
SELECT *
FROM level4
WHERE sum_chek_low_median > sum_chek_high_median

-- 826.«Індекс внутрішньої зради клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,AVG(sum_chek) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,median_chek / avg_chek as betrayal_index
FROm level3)
SELECT *
FROm level4
WHERE betrayal_index < 0.75