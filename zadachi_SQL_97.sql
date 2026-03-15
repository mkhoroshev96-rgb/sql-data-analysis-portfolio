-- 627. «Клієнт з ефектом зсуву центру ваги»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,unit_price
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
JOIN level2 USING (customer_id,order_id)
WHERE count_order >= 8),
level4 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by unit_price) as median_price
FROM level3
GROUP BY customer_id, halfs),
level5 as(SELECT *
FROM level3
JOIN level4 USING (customer_id, halfs)),
level6 as(SELECT customer_id
       ,ROUND(AVG(median_price) FILTER (WHERE halfs = 'first')::numeric,2) as median_price_first
	   ,ROUND(AVG(median_price) FILTER (WHERE halfs = 'second')::numeric,2) as median_price_second
FROM level5
GROUP By customer_id),
level7 as(SELECT *
       ,ROUND(ABS((median_price_second - median_price_first) / median_price_first)::numeric,2) as diff_medians
FROm level6)
SELECT *
FROM level7
WHERE diff_medians > 0.2

-- 628. «Клієнт з ефектом розмивання екстремуму»

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
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((total_revenue - max_chek) / (count_order - 1)::numeric,2) as avg_chek_ohne_max_chek
FROm level2),
level4 as(SELECT *
       ,ROUND((1 - avg_chek_ohne_max_chek / avg_chek)::numeric,4) as fallen_percent
FROm level3)
SELECT *
FROm level4
WHERE fallen_percent > 0.3

-- 629. «Клієнт з ефектом інверсії концентрації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(sum(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
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
WHERE count_order >= 7),
level3 as(SELECT customer_id
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'first') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second') as total_revenue_second
	   ,MAX(sum_chek) FILTER (WHERE halfs = 'first') as max_chek_first
	   ,MAX(sum_chek) FILTER (WHERE halfs = 'second') as max_chek_second
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,max_chek_first / total_revenue_first as share_first
	   ,max_chek_second / total_revenue_second as share_second
FROm level3),
level5 as(SELECT *
       ,ROUND((share_second / share_first)::numeric,4) as diff_share
FROM level4)
SELECT *
FROm level5
WHERE diff_share >= 1.25

-- 630. «Клієнт з ефектом структурного розвороту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,(p.unit_price * quantity * (1-discount)) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,order_id
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT customer_id
       ,category_id
	   ,SUM(chek) FILTER (WHERE halfs = 'first') as sum_chek_category_first
	   ,SUM(chek) FILTER (WHERE halfs = 'second') as sum_chek_category_second
FROM level3
GROUP BY customer_id, category_id),
level5 as(SELECT customer_id
       ,category_id
	   ,sum_chek_category_first
       ,DENSE_RANK () OVER (partition by customer_id order by sum_chek_category_first DESC) as rank_chek_first
FROm level4
WHERE sum_chek_category_first is not null),
level6 as(SELECT *
FROm level5
WHERE rank_chek_first = 1),
level7 as(SELECT customer_id
       ,category_id
	   ,sum_chek_category_second
	   ,DENSE_RANK () OVER (partition by customer_id order by sum_chek_category_second DESC) as ranK_chek_second
FROm level4
WHERE sum_chek_category_second is not null),
level8 as(SELECT *
FROm level7
WHERE rank_chek_second = 1)
SELECT l6.customer_id
       ,l6.category_id
	   ,l6.sum_chek_category_first
	   ,l6.rank_chek_first
	   ,l8.category_id
	   ,l8.sum_chek_category_second
	   ,l8.rank_chek_second
FROM level6 l6
RIGHT JOIN level8 l8 USING (customer_id)
WHERE l6.category_id <> l8.category_id

-- 631. «Клієнт з ефектом латентної поляризації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
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
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,AVG(sum_chek) FILTER (WHERE halfs = 'first') as avg_chek_first
	   ,STDDEV(sum_chek) FILTER (WHERE halfs = 'first') as stddev_chek_first
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
       ,avg_chek_first - stddev_chek_first as lower_bound
	   ,avg_chek_first + stddev_chek_first as upper_bound
FROm level2
JOIN level3 USING (customer_id)
WHERE halfs = 'second'),
level5 as(SELECT *
       ,case when sum_chek < lower_bound OR sum_chek > upper_bound THEN 1 
	   ELSE 0 END as flag_lower_upper 
FROM level4),
level6 as(SELECT *
       ,SUM(flag_lower_upper) OVER (partition by customer_id) as sum_flag_lower_upper
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order_second
FROM level5),
level7 as(SELECT *
       ,ROUND((sum_flag_lower_upper::numeric / count_order_second::numeric),2) as ratio
FROm level6)
SELECT *
FROm level7
WHERE ratio >= 0.5
