-- 558. «Замовлення-хамелеон» version 2.0

WITH level1 as(SELECT customer_id
       ,category_id
	   ,order_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p  USING (product_id)
JOIN categories USING (category_id)
ORDER by customer_id),
level2 as(SELECT category_id
       ,ROUND(AVG(chek)::numeric,2) as avg_chek_category
FROm level1
GROUP BY category_id),
level3 as(SELECT *
       ,ROUND(AVG(chek) OVER (partition by customer_id)::numeric,2) as avg_chek_customer
	   ,SUM(chek) OVER (partition by customer_id, order_id) as sum_chek_order
FROM level1
JOIN level2 USING (category_id)),
level4 as(SELECT *
       ,case when (sum_chek_order < avg_chek_customer AND chek > avg_chek_category) OR (sum_chek_order > avg_chek_customer AND chek < avg_chek_category) THEN 1 
	   ELSE 0 END as flags_cheks
FROm level3),
level5 as(SELECT *
FROM level4
WHERE flags_cheks = 1),
level6 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROm orders
GROUP By customer_id)
SELECT *
FROM level5
JOIN level6 USING (customer_id)
WHERE count_order >= 6

-- 559. «Клієнт з ілюзією різноманіття»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,category_id
	   ,ROUND((p.unit_price * quantity * (1- discount))::numeric,2) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
ORDER BY customer_id),
level2 as(SELECT customer_id
       ,COUNT(DISTINCT category_id) as count_unik_category
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id, category_id) as revenue_per_category
	   ,SUM(chek) OVER (partition by customer_id) as total_revenue
FROM level1
JOIN level2 USING (customer_id)),
level4 as(SELECT DISTINCT customer_id
       ,category_id
	   ,count_unik_category
	   ,revenue_per_category
	   ,total_revenue
	   ,ROUND((revenue_per_category / total_revenue)::numeric,2) as ratio_revenue
FROM level3
ORDER BY customer_id),
level5 as(SELECT *
       ,MAX(ratio_revenue) OVER (partition by customer_id) as max_ratio_revenue
FROM level4),
level6 as(SELECT *
FROM level5
WHERE count_unik_category >= 4 AND max_ratio_revenue >= 0.7),
level7 as(SELECT customer_id
       ,COUNT (order_id) as count_order
FROM orders
GROUP By customer_id)
SELECT *
FROm level6
JOIn level7 USING (customer_id)
WHERE count_order >= 6

-- 560. «Категорія з фальшивою лояльністю»

WITH level1 as(SELECT category_id
       ,customer_id
	   ,order_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
ORDER BY category_id),
level2 as(SELECT category_id
       ,COUNT(distinct customer_id) as count_unik_customer
FROm level1
GROUP BY category_id),
level3 as(SELECT *
FROm level1
JOIN level2 USING (category_id)),
level4 as(SELECT category_id
       ,customer_id
	   ,COUNT(order_id) as count_order
FROM level1
GROUP BY category_id, customer_id),
level5 as(SELECT *
       ,ntile(5) OVER (partition by category_id order by chek desc) as ntile_chek
	   ,SUM(chek) OVER (partition by category_id) as total_revenue_category
FROM level3
JOIN level4 USING (category_id, customer_id)),
level6 as(SELECT *
       ,SUM(chek) FILTER (WHERE ntile_chek = 1) OVER (partition by category_id) as revenue_top_20_percent
	   ,ROUND(AVG(count_order) OVER (partition by category_id)::numeric,2) as avg_count_order
	   ,ROUND(AVG(count_order) OVER ()::numeric,2) as global_avg_count_order
FROm level5),
level7 as(SELECT *
       ,ROUND((revenue_top_20_percent / total_revenue_category)::numeric,2) as ratio_revenue_top
FROM level6)
SELECT *
FROm level7
WHERE avg_count_order > global_avg_count_order AND ratio_revenue_top >= 0.6

-- 561. «Категорія з ефектом Симпсона (реальний)»

WITH level1 as(SELECT category_id
       ,ship_country
	   ,customer_id
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIn order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT * 
       ,ROUND(AVG(chek) OVER (partition by category_id)::numeric,2) as avg_chek_category
	   ,ROUND(AVG(chek) OVER (partition by category_id, ship_country)::numeric,2) as avg_chek_category_country
	   ,ROUND(AVG(chek) OVER (partition by category_id, ship_country, customer_id)::numeric,2) as avg_chek_category_country_customer
FROm level1),
level3 as(SELECT category_id
       ,ROUND(AVG(avg_chek_category) OVER ()::numeric,2) as global_avg_chek_category
FROm level2),
level4 as(SELECT *
FROm level2
JOIN level3 USING (category_id)),
level5 as(SELECT ship_country
       ,ROUND(AVG(avg_chek_category_country)::numeric,2) as global_avg_chek_country_category
FROM level4
GROUP BY ship_country),
level6 as(SELECT *
       ,case when avg_chek_category_country_customer < global_avg_chek_category THEN 1
	   ELSE 0 END as flags
FROm level4
JOIN level5 USING (ship_country)
WHERE avg_chek_category > global_avg_chek_category AND avg_chek_category_country > global_avg_chek_country_category),
level7 as(SELECT *
       ,SUM(flags) OVER (partition by category_id) as sum_flags
	   ,COUNT(customer_id) OVER (partition by category_id) as total_count_customer
FROm level6),
level8 as(SELECT *
       ,ROUND((sum_flags::numeric / total_count_customer::numeric),2) as ratio
FROm level7)
SELECT *
FROm level8
WHERE ratio >= 0.6

-- 562. «Клієнт із зсувом центру»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND(ABS((sum_chek - median_chek) / median_chek) ::numeric,2) as diff_chek
	   ,ROUND(ABS((avg_chek - median_chek) / median_chek)::numeric,2) as diff_avg_median_chek 
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,case when diff_chek >= 0.2 THEN 1 ELSE 0 END as flag_high
FROm level3
WHERE diff_avg_median_chek <= 0.05),
level5 as(SELECT *
       ,SUM(flag_high) OVER (partition by customer_id) as sum_flag_high
FROm level4),
level6 as(SELECT *
       ,ROUND((sum_flag_high::numeric / count_order::numeric),2) as ratio
FROm level5)
SELECT *
FROM level6
WHERE ratio >= 0.8

-- 563. «Замовлення без впливу»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND((total_revenue - sum_chek) / (count_order - 1)::numeric,2) as avg_chek_ohne_order
FROM level2),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_ohne_order - avg_chek) / avg_chek)::numeric,2) as diff_order_ohne_chek
FROm level3),
level5 as(SELECT *
       ,ROUND((sum_chek / avg_chek)::numeric,2) as diff_chek
FROM level4
WHERE diff_order_ohne_chek <= 0.03)
SELECT *
FROm level5
WHERE diff_chek >= 1.25

-- 564. «Клієнт з ефектом компенсації»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM (unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,sum_chek - avg_chek as diff_chek
	   ,ROUND(ABS((avg_chek - median_chek) / median_chek)::numeric,2) as diff_median_avg
FROm level1
JOIn level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT *
       ,case when sum_chek > avg_chek THEN 'high'
	   when sum_chek < avg_chek THEN 'low'
	   when sum_chek = avg_chek THEN 'equal'
	   END as gradation
FROm level3
WHERE diff_median_avg <= 0.05),
level5 as(SELECT customer_id
       ,COUNT(order_id) FILTER (WHERE gradation = 'high')  as count_order_high
	   ,COUNT(order_id) FILTER (WHERE gradation = 'low') as count_order_low
FROm level4
GROUP By customer_id),
level6 as(SELECT *
       ,ROUND((count_order_high::numeric / count_order::numeric),2) as ratio_high
	   ,ROUND((count_order_low::numeric / count_order::numeric),2) as ratio_low
FROm level4
JOIN level5 USING (customer_id))
SELECT *
FROm level6
WHERE ratio_high >= 0.4 AND ratio_low >= 0.4

-- 565. «Клієнт з ефектом втраченої ієрархії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by order_date) as rank_date
	   ,DENSE_RANK () OVER (partition by customer_id order by sum_chek DESC) as rank_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,ROUND((stddev_chek / avg_chek)::numeric,2) as cv
FROm level2),
level4 as(SELECT *
FROm level3
WHERE cv >= 0.15),
level5 as(SELECT customer_id
       ,ROUND(ABS(corr(rank_date, rank_chek))::numeric,2) as corr_date_chek
FROM level4
GROUP By customer_id)
SELECT *
FROm level5
WHERE corr_date_chek <= 0.1
