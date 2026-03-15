-- 580. «Замовлення з фальшивою терміновістю»

with level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,shipped_date - order_date as delivery_days
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) from level1) as global_median_quantity
	   ,ROUND(AVG(delivery_days) OVER ()::numeric,2) as global_avg_delivery
FROM level1)
SELECT *
FROm level2
WHERE delivery_days > global_avg_delivery AND sum_quantity <= global_median_quantity

-- 581. «Замовлення з маскованою знижкою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,ROUND((unit_price * quantity * discount)::numeric,2) as discount_amount
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(discount_amount) OVER (partition by customer_id, order_id) as total_discount_amount
FROm level1),
level3 as(SELECT *
       ,MAX(discount_amount) OVER (partition by customer_id, order_id) as max_discount_amount
FROm level2),
level4 as(SELECT *
       ,ROUND((max_discount_amount / total_discount_amount)::numeric,2) as ratio_discount
FROM level3)
SELECT *
FROM level4
WHERE total_discount_amount > 0 AND ratio_discount >= 0.8

-- 582. «Замовлення з перевернутою вигодою»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,unit_price
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as item_revenue
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id, order_id order by unit_price DESC) as rank_price
	   ,DENSE_RANK () OVER (partition by customer_id, order_id order by item_revenue DESC) as rank_revenue
FROm level1)
SELECT *
FROm level2
WHERE (rank_price = 1 AND rank_revenue <> 1) OR (rank_price <> 1 AND rank_revenue = 1)

-- 583. «Клієнт із “паразитною” категорією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,category_id
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,case when category_id = 1 THEN 1 ELSE 0 END as flag_1
	   ,case when category_id = 2 THEN 1 ELSE 0 END as flag_2
	   ,case when category_id = 3 THEN 1 ELSE 0 END as flag_3
	   ,case when category_id = 4 THEN 1 ELSE 0 END as flag_4
	   ,case when category_id = 5 THEN 1 ELSE 0 END as flag_5
	   ,case when category_id = 6 THEN 1 ELSE 0 END as flag_6
	   ,case when category_id = 7 THEN 1 ELSE 0 END as flag_7
	   ,case when category_id = 8 THEN 1 ELSE 0 END as flag_8
FROM level1),
level3 as(SELECT *
       ,SUM(flag_1) OVER (partition by customer_id) as sum_flag_1
	   ,SUM(flag_2) OVER (partition by customer_id) as sum_flag_2
	   ,SUM(flag_3) OVER (partition by customer_id) as sum_flag_3
	   ,SUM(flag_4) OVER (partition by customer_id) as sum_flag_4
	   ,sum(flag_5) OVER (partition by customer_id) as sum_flag_5
	   ,sum(flag_6) OVER (partition by customer_id) as sum_flag_6
	   ,sum(flag_7) OVER (partition by customer_id) as sum_flag_7
	   ,sum(flag_8) OVER (partition by customer_id) as sum_flag_8
FROm level2),
level4 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROm orders
GROUP By customer_id),
level5 as(SELECT DISTINCT customer_id
       ,sum_flag_1
	   ,sum_flag_2
	   ,sum_flag_3
	   ,sum_flag_4
	   ,sum_flag_5
	   ,sum_flag_6
	   ,sum_flag_7
	   ,sum_flag_8
	   ,count_order
FROm level3
JOIN level4 USING (customer_id)
WHERE count_order >= 6),
level6 as(SELECT *
       ,ROUND((sum_flag_1::numeric / count_order::numeric),2) as ratio_1
	   ,ROUND((sum_flag_2::numeric / count_order::numeric),2) as ratio_2
	   ,ROUND((sum_flag_3::numeric / count_order::numeric),2) as ratio_3
	   ,ROUND((sum_flag_4::numeric / count_order::numeric),2) as ratio_4
	   ,ROUND((sum_flag_5::numeric / count_order::numeric),2) as ratio_5
	   ,ROUND((sum_flag_6::numeric / count_order::numeric),2) as ratio_6
	   ,ROUND((sum_flag_7::numeric / count_order::numeric),2) as ratio_7
	   ,ROUND((sum_flag_8::numeric / count_order::numeric),2) as ratio_8
FROM level5)
SELECT *
FROM level6
WHERE ratio_1 >= 0.8 OR ratio_2 >= 0.8 OR ratio_3 >= 0.8 OR ratio_4 >= 0.8
OR ratio_5 >= 0.8 OR ratio_6 >= 0.8 OR ratio_7 >= 0.8 OR ratio_8 >= 0.8

-- 584. «Клієнт з ефектом звикання до знижки»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,avg(discount) as avg_discount
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,MIN(case when avg_discount > 0 THEN order_date END) OVER (partition by customer_id) as date_first_discount
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,case when order_date < date_first_discount THEN 'befor'
	   when order_date > date_first_discount THEN 'after'
	   when order_date = date_first_discount THEN 'equal'
	   END as gradation
FROM level2
WHERE date_first_discount is not null)
SELECT customer_id
       ,ROUND(AVG(avg_discount) FILTER (WHERE gradation = 'before')::numeric,2) as avg_discount_before
	   ,ROUND(AVG(avg_discount) FILTER (WHERE gradation = 'after')::numeric,2) as avg_discount_after
FROm level3
GROUP BY customer_id

-- 585. «Клієнт з ефектом втраченої різноманітності»

WITH level1 as (SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity 
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_products
FROm level1
GROUP BY customer_id, order_id),
level3 as(SELECT *
       ,SUM(quantity) OVER (partition by customer_id, order_id) as sum_quantity
FROm level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT DISTINCT customer_id
       ,order_id
	   ,order_date
	   ,sum_quantity
	   ,count_unik_products
FROm level3),
level5 as(SELECT *
       ,ntile(3) OVER (partition by customer_id order by order_date) as ntile_3
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level4),
level6 as(SELECT *
FROM level5
WHERE count_order >= 10),
level7 as(SELECT customer_id
       ,ROUND(AVG(count_unik_products) FILTER (WHERE ntile_3 = 1)::numeric,2) as avg_count_product_1
	   ,ROUND(AVG(count_unik_products) FILTER (WHERE ntile_3 = 3)::numeric,2) as avg_count_product_3
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE ntile_3 = 1)::numeric,2) as avg_quantity_1
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE ntile_3 = 3)::numeric,2) as avg_quantity_3
FROm level6
GROUP By customer_id)
SELECT *
FROM level7
WHERE avg_count_product_3 < avg_count_product_1 
AND avg_quantity_3 >= avg_quantity_1

-- 586. «Клієнт з ефектом помилкової стабільності»

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
WHERE count_order >= 8),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as stddev_chek_first
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as stddev_chek_second
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
FROM level3)
SELECT *
FROm level4
WHERE diff_chek <= 0.05 AND stddev_chek_second > stddev_chek_first

-- 587. «Клієнт з ефектом зламаної інерції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
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
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median_quantity
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,case when sum_quantity > median_quantity THEN 'high'
	   when sum_quantity <= median_quantity THEN 'low'
	   END as gradation
FROm level2
JOIN level3 USING (customer_id)),
level5 as(SELECT *
       ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROm level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_quantity_second
FROm level5
GROUP By customer_id),
level7 as(SELECT customer_id
       ,ROUND(AVG(next_quantity) FILTER (WHERE halfs = 'first')::numeric,2) as avg_next_quantity_first
	   ,ROUND(AVG(next_quantity) FILTER (WHERE halfs = 'second')::numeric,2) as avg_next_quantity_second
FROM level5
JOIN level6 USING (customer_id)
WHERE gradation = 'high'
GROUP By customer_id)
SELECT *
FROm level6
JOIN level7 USING (customer_id)
WHERE avg_next_quantity_first is not null AND  avg_next_quantity_second is not null
AND avg_next_quantity_first > avg_quantity_first AND avg_next_quantity_second <= avg_quantity_second

