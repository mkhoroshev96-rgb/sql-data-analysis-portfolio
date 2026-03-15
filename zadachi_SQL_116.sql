-- 774. «Retention через грошову інерцію»

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
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,SUM(sum_chek) FILTER (WHERE halfs = 'first') as total_revenue_first
	   ,SUM(sum_chek) FILTER (WHERE halfs = 'second') as total_revenue_second
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,total_revenue_second / total_revenue_first as ratio
FROM level3)
SELECT *
       ,case when ratio > 1 THEN 'progress'
	   when ratio < 1 THEN 'degradation'
	   when ratio = 1 THEN 'stagnation'
	   END as gradation
FROM level4
ORDER BY ratio

-- 775. «Ілюзія середнього чеку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as avg_order_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(avg_order_chek) OVER (partition by customer_id) as avg_aov
	   ,STDDEV(avg_order_chek) OVER (partition by customer_id) as stddev_aov
FROm level1
WHERE count_order >= 8),
level3 as(SELECT DISTINCT customer_id
	   ,avg_aov
	   ,stddev_aov
FROM level2),
level4 as(SELECT DISTINCT customer_id
       ,avg_aov
	   ,stddev_aov
FROM level3)
SELECT *
       ,stddev_aov / avg_aov as cv_aov
FROM level4
ORDER BY cv_aov DESC

-- 776. «Retention без повернення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,FIRST_VALUE(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) as first_date_customer
	   ,FIRST_VALUE(order_date) OVER (partition by customer_id order by order_date DESC) as last_date_customer
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders),
level2 as(SELECT *
       ,(last_date_customer - first_date_customer) + 1 as activity_day
FROM level1
WHERE count_order >= 5),
level3 as(SELECT DISTINCT customer_id
       ,first_date_customer
	   ,last_date_customer
	   ,count_order
	   ,activity_day
FROm level2
WHERE activity_day >= 30)
SELECT *
       ,count_order::numeric / activity_day::numeric as repeat_rate
FROM level3
ORDER BY repeat_rate DESC

-- 777. «Знижкова еластичність клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,AVG(discount) as avg_discount
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
FROm level1
WHERE count_order >= 12)
SELECT customer_id
       ,corr(avg_discount, sum_quantity) as discount_sensitivity
FROm level2
GROUP By customer_id
ORDER BY discount_sensitivity DESC

-- 778. «Ілюзія диверсифікації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING(order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, product_id) as sum_chek_product_customer
	   ,SUM(chek) OVER (partition by customer_id) as total_revenue
FROM level1),
level3 as(SELECT DISTINCT customer_id
	   ,product_id
	   ,sum_chek_product_customer
	   ,total_revenue
FROM level2),
level4 as(SELECT *
       ,sum_chek_product_customer / total_revenue as ratio
FROM level3
ORDER BY customer_id, product_id),
level5 as(SELECT *
       ,ratio * ratio as ratio_sqrt
FROM level4),
level6 as(SELECT *
       ,SUM(ratio_sqrt) OVER (partition by customer_id) as hhi
FROM level5),
level7 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP BY customer_id)
SELECT DISTINCT customer_id
       ,hhi
FROM level6
JOIN level7 USING (customer_id)
WHERE count_order >= 8
ORDER BY hhi DESC

-- 779. «Фантомна лояльність»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_chek
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,1 - (max_chek / total_chek) as consistency_ratio
FROm level2)
SELECT DISTINCT customer_id
       ,total_chek
	   ,max_chek
	   ,consistency_ratio
	   ,case when consistency_ratio < 0.2 THEN 'high_risk'
	   when consistency_ratio BETWEEN 0.2 AND 0.8 THEN 'normal_risk'
	   when consistency_ratio > 0.8 THEN 'low_risk'
	   END as gradation
FROM level3
ORDER BY consistency_ratio DESC

-- 780. «Повільне згасання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders),
level2 as(SELECT *
       ,order_date - prev_date as interval
FROM level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_interval
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM level2
WHERE interval is not null),
level4 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level3),
level5 as(SELECT customer_id
       ,AVG(interval) FILTER (WHERE halfs = 'first') as avg_interval_first
	   ,AVG(interval) FILTER (WHERE halfs = 'second') as avg_interval_second 
FROm level4
GROUP BY customer_id),
level6 as(SELECT *
       ,avg_interval_second / avg_interval_first as decay_index
FROM level5)
SELECT *
       ,case when decay_index > 1.1 THEN 'low_bay'
	   when decay_index between 0.9 AND 1.1 THEN 'normal_bay'
	   when decay_index < 0.9 THEN 'high_bay'
	   END as gradation
FROM level6
ORDER BY decay_index DESC

-- 781. «Категоріальний зсув»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,(p.unit_price * quantity * (1-discount)) as chek
FROm orders
Join order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
ORDER BY customer_id),
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
level4 as(SELECT customer_id
       ,category_id
	   ,SUM(chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as total_revenue_first
	   ,SUM(chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as total_revenue_second
	   ,SUM(chek) FILTER (WHERE halfs = 'first') OVER (partition by customer_id, category_id) as chek_per_category_first
	   ,SUM(chek) FILTER (WHERE halfs = 'second') OVER (partition by customer_id, category_id) as chek_per_category_second
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,category_id
	   ,total_revenue_first
	   ,total_revenue_second
	   ,chek_per_category_first
	   ,chek_per_category_second
FROm level4),
level6 as(SELECT *
       ,coalesce((chek_per_category_first / total_revenue_first),0) as ratio_first
	   ,coalesce((chek_per_category_second / total_revenue_second),0) as ratio_second
FROM level5),
level7 as(SELECT *
       ,ABS(ratio_first - ratio_second) as abs_diff_ratio
FROM level6),
level8 as(SELECT *
       ,SUM(abs_diff_ratio) OVER (partition by customer_id) as sum_diff_ratio
FROM level7)
SELECT DISTINCT customer_id
       ,sum_diff_ratio
FROM level8
ORDER BY sum_diff_ratio DESC 

