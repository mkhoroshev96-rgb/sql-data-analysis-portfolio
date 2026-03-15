-- 662. «Клієнт із ефектом поступового здешевлення кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND((SUM(unit_price * quantity * (1-discount)) / SUM(quantity))::numeric,2) as price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,FIRST_VALUE (sum_quantity) OVER (partition by customer_id order by order_date) as first_quantity
	   ,FIRST_VALUE (sum_quantity) OVER (partition by customer_id order by order_date DESC) as last_quantity
	   ,FIRST_VALUE (price) OVER (partition by customer_id order by order_date) as first_price
	   ,FIRST_VALUE (price) OVER (partition by customer_id order by order_date DESC) as last_price
FROm level1
WHERE count_order >= 12)
SELECT DISTINCT customer_id
       ,first_quantity
	   ,last_quantity
	   ,first_price
	   ,last_price
FROm level2
WHERE last_quantity >= first_quantity AND last_price < 0.75 * first_price

-- 663. «Клієнт із ефектом періодичного обнулення»

with level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek,1) OVER (partition by customer_id order by order_date) as prev_1_chek
	   ,LAG(sum_chek,2) OVER (partition by customer_id order by order_date) as prev_2_chek
	   ,LAG(sum_chek,3) OVER (partition by customer_id order by order_date) as prev_3_chek
FROm level1
WHERE count_order >= 10),
level3 as(SELECT *
       ,ROUND(((prev_1_chek + prev_2_chek + prev_3_chek) / 3)::numeric,2) as prev_avg_chek
FROm level2
WHERE prev_3_chek is not null),
level4 as(SELECT *
       ,case when sum_chek < 0.3 * prev_avg_chek THEN 1 ELSE 0 END as flag_chek
FROm level3),
level5 as(SELECT * 
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level4)
SELECT *
FROm level5
WHERE sum_flag_chek >= 2

-- 664. «Клієнт із ефектом структурного зсуву категорій»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_id
	   ,product_id
FROm orders
JOIN order_details USING (order_id)
JOIN products USING (product_id)
JOIn categories USING (category_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT category_id) as count_unik_category_order
FROm level1
GROUP By customer_id, order_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT customer_id
       ,COUNT(DISTINCT category_id) as count_unik_category_customer
FROM level1
GROUP BY customer_id),
level5 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
       ,count_unik_category_order
	   ,count_unik_category_customer
FROM level3
JOIN level4 USING (customer_id)),
level6 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level5),
level7 as(SELECT *
       ,ROUND(AVG(count_unik_category_order) OVER (partition by customer_id)::numeric,2) as avg_unik_category_last_order
FROm level6
WHERE count_order >= 12 AND rn_invert <= 4 AND count_unik_category_customer >= 3)
SELECT *
FROm level7
WHERE avg_unik_category_last_order = 1

-- 665. «Клієнт із ефектом концентрації витрат»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROm level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,max_chek / total_revenue as ratio
FROm level2)
SELECT *
FROm level3
WHERE ratio >= 0.35

-- 666. «Клієнт із ефектом внутрішньої цінової поляризації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,unit_price
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT DISTINCT product_id
       ,ROUND(AVG(unit_price)::numeric,2) as price
FROm orders
JOIN order_details USING (order_id)
GROUP By product_id),
level3 as(SELECT *
       ,NTILE(10) OVER (order by price) as ntile10
FROm level2),
level4 as(SELECT *
       ,case when ntile10 <= 3 THEN 'low_price'
	   when ntile10 >= 4 AND ntile10 <= 7 THEN 'medium_price'
	   when ntile10 >= 8 THEN 'high_price'
	   END as gradation
FROM level3),
level5 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as total_bay
	   ,COUNT(product_id) FILTER (WHERE gradation = 'low_price') OVER (partition by customer_id) as count_low_price
	   ,COUNT(product_id) FILTER (WHERE gradation = 'medium_price') OVER (partition by customer_id) as count_medium_price
	   ,COUNT(product_id) FILTER (WHERE gradation = 'high_price') OVER (partition by customer_id) as count_high_price
FROm level1
JOIN level4 USING (product_id)),
level6 as(SELECT DISTINCT customer_id
       ,total_bay
	   ,count_low_price
	   ,count_medium_price
	   ,count_high_price
	   ,ROUND((count_low_price::numeric / total_bay::numeric),4) as ratio_low_price
	   ,ROUND((count_medium_price::numeric / total_bay::numeric),4) as ratio_medium_price
	   ,ROUND((count_high_price::numeric / total_bay::numeric),4) as ratio_high_price
FROm level5)
SELECT *
FROM level6
WHERE ratio_medium_price < 0.2 AND ratio_low_price + ratio_high_price >= 0.8

-- 667. «Клієнт із ефектом прихованого канібалізму категорії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,category_id
	   ,product_id
	   ,p.unit_price
	   ,quantity
FROM orders
JOIn order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,category_id
	   ,ROUND(AVG(unit_price) OVER (partition by customer_id, category_id)::numeric,2) as avg_price_category
	   ,SUM(quantity) OVER (partition by customer_id, category_id) as sum_quantity_category
	   ,SUM(quantity) OVER (partition by customer_id) as total_quantity
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,category_id
	   ,avg_price_category
	   ,sum_quantity_category
	   ,total_quantity
FROm level2
ORDER BY customer_id),
level4 as(SELECT *
       ,ROUND((sum_quantity_category::numeric / total_quantity::numeric),4) as ratio_quantity
fROM level3),
level5 as(SELECT *
       ,MAX(ratio_quantity) OVER (partition by customer_id) as max_quantity
FROm level4),
level6 as(SELECT *
       ,case when ratio_quantity = max_quantity THEN 'top_category'
	   ELSE 'other' END as gradation
FROm level5
WHERE max_quantity >= 0.4),
level7 as(SELECT *
       ,ROUND(AVG(avg_price_category) FILTER (WHERE gradation = 'top_category') OVER (partition by customer_id)::numeric,4) as avg_price_top_category
	   ,ROUND(AVG(avg_price_category) FILTER (WHERE gradation = 'other') OVER (partition by customer_id)::numeric,4) as avg_price_other_category
FROm level6)
SELECT *
FROm level7
WHERE avg_price_top_category < avg_price_other_category

-- 668. «Клієнт із ефектом різкого перерозподілу кошика»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,category_id
	   ,p.product_id
	   ,(p.unit_price * quantity * (1-discount)) as chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)),
level2 as(SELECT customer_id
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders),
level3 as(SELECT *
FROm level1
JOIN level2 USING (customer_id)
WHERE count_order >= 10
ORDER BY customer_id),
level4 as(SELECT DISTINCT customer_id
       ,order_id
       ,category_id
	   ,chek
FROm level3
ORDER BY customer_id),
level5 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id,order_id, category_id) as chek_per_category_in_order
	   ,SUM(chek) OVER (partition by customer_id, order_id) as chek_per_order
FROM level4),
level6 as(SELECT *
       ,ROUND((chek_per_category_in_order / chek_per_order)::numeric,4) as ratio
FROm level5),
level7 as(SELECT *
       ,case when ratio >= 0.7 THEN 1 ELSE 0 END as flag_ratio
FROm level6),
level8 as(SELECT *
       ,SUM(flag_ratio) OVER (partition by customer_id) as sum_flag_ratio
FROM level7),
level9 as(SELECT *
       ,ROUND(AVG(ratio) FILTER (WHERE ratio < 0.7) OVER (partition by customer_id, category_id)::numeric,4) as avg_ratio_category
	   ,MAX(ratio) OVER (partition by customer_id, category_id) as max_ratio
FROm level8
WHERE sum_flag_ratio >= 1)
SELECT *
FROm level9
WHERE avg_ratio_category <= 0.4 AND max_ratio >= 0.7
