-- 572. «Замовлення з ефектом внутрішнього конфлікту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,unit_price
	   ,discount
	   ,COUNT(product_id) OVER (partition by customer_id, order_id) as count_product
FROm orders
JOIN order_details USING (order_id)
ORDER BY customer_id),
level2 as(SELECT *
       ,case when discount > 0 THEN 'product_with_discount'
	   when discount = 0 then 'product_ohne_discount'
	   END as gradation
FROM level1
WHERE count_product >= 3),
level3 as(SELECT customer_id
       ,order_id
	   ,ROUND(AVG(unit_price) FILTER (WHERE gradation = 'product_with_discount')::numeric,2) as avg_price_with_discount
	   ,ROUND(AVG(unit_price) FILTER (WHERE gradation = 'product_ohne_discount')::numeric,2) as avg_price_ohne_discount
	   ,COUNT(product_id) FILTER (WHERE gradation = 'product_with_discount') as count_product_with_discount
	   ,COUNT(product_id) FILTER (WHERE gradation = 'product_ohne_discount') as count_product_ohne_discount
FROM level2
GROUP BY customer_id, order_id)
SELECT *
FROM level3
WHERE avg_price_with_discount is not null AND avg_price_ohne_discount is not null
AND count_product_with_discount >= 1 AND count_product_ohne_discount >= 1
AND avg_price_ohne_discount >= 1.5 * avg_price_with_discount

-- 573. «Замовлення з ефектом розмитої пріоритетності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,category_id
	   ,COUNT(product_id) OVER (partition by customer_id, order_id) as count_product
FROM orders
JOIN order_details USING(order_id)
JOIN products USING (product_id)
JOIN categories USING (category_id)
ORDER BY customer_id),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT category_id) as count_unik_category
FROm level1
GROUP BY customer_id, order_id),
level3 as(SELECT *
       ,COUNT(category_id) OVER (partition by customer_id, order_id,category_id) as count_category_in_order
FROM level1
JOIN level2 USING(customer_id, order_id)
WHERE count_product >= 4 AND count_unik_category >= 3),
level4 as(SELECT DISTINCT customer_id
       ,order_id
	   ,category_id
	   ,count_product
	   ,count_unik_category
	   ,count_category_in_order
	   ,ROUND((count_category_in_order::numeric / count_product)::numeric,2) as ratio
FROm level3),
level5 as(SELECT *
       ,MAX(ratio) OVER (partition by customer_id, order_id) as max_ratio_order
FROm level4)
SELECT *
FROm level5
WHERE max_ratio_order <= 0.4

-- 574. «Замовлення з ефектом хибної економії»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,discount
	   ,ROUND((unit_price * quantity * (discount))::numeric,2) as chek
	   ,ROUND((unit_price * quantity)::numeric,2) as chek_ohne_discount
	   ,COUNT(product_id) OVER (partition by customer_id, order_id) as count_product
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,ROUND(sum(chek) / sum(chek_ohne_discount)::numeric,4) as real_saving
FROM level1
GROUP By customer_id, order_id),
level3 as(SELECT *
       ,COUNT(product_id) FILTER (WHERE discount > 0) OVER (partition by customer_id, order_id) as count_product_with_discount
FROm level1
JOIN level2 USING (customer_id, order_id)
WHERE count_product >= 3 AND real_saving <= 0.1),
level4 as(SELECT *
       ,ROUND((count_product_with_discount::numeric / count_product::numeric),2) as discount_share
FROM level3)
SELECT *
FROM level4
WHERE discount_share >= 0.6

-- 575. «Клієнт з ефектом втрати різноманіття»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(distinct product_id) as count_unik_product_in_order
FROM level1
GROUP By customer_id, order_id),
level3 as(SELECT distinct customer_id
       ,order_id
	   ,order_date
	   ,count_unik_product_in_order
FROm level1
JOIN level2 USING (customer_id, order_id)),
level4 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm level3),
level5 as(SELECT *
       ,ntile(3) OVER (partition by customer_id order by order_date) as ntile_3
FROm level4
WHERE count_order >= 10),
level6 as(SELECT customer_id
       ,ROUND(AVG(count_unik_product_in_order) FILTER (where ntile_3 = 1)::numeric,2) as avg_count_unik_1
	   ,ROUND(AVG(count_unik_product_in_order) FILTER (where ntile_3 = 2)::numeric,2) as avg_count_unik_2
	   ,ROUND(AVG(count_unik_product_in_order) FILTER (where ntile_3 = 3)::numeric,2) as avg_count_unik_3
FROM level5
GROUP By customer_id),
level7 as(SELECT *
FROM level6
WHERE avg_count_unik_3 <= avg_count_unik_1 * 0.5),
level8 as(SELECT *
       ,case when avg_count_unik_2 < avg_count_unik_1 and avg_count_unik_2 > avg_count_unik_3 THEN 'yes'
	   else 'no' END as gradation
FROM level7)
SELECT *
FROm level8
WHERE gradation = 'yes'

-- 576. «Клієнт із втраченим імпульсом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,MIN(case when sum_quantity = max_quantity THEN order_date END) OVER (partition by customer_id) as first_date_peak
FROm level2),
level4 as(SELECT *
       ,case when order_date < first_date_peak THEN 'before'
	   when order_date > first_date_peak THEN 'after'
	   when order_date = first_date_peak THEN 'equal'
	   END as gradation
FROm level3),
level5 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (where gradation = 'before')::numeric,2) as avg_quantity_before
	   ,ROUND(AVG(sum_quantity) FILTER (where gradation = 'after')::numeric,2) as avg_quantity_after
FROM level4
WHERE gradation IN ('before', 'after')
GROUP BY customer_id),
level6 as(SELECT *
FROm level4
JOIN level5 USING (customer_id)
WHERE avg_quantity_after < avg_quantity_before),
level7 as(SELECT *
       ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROm level6
WHERE gradation = 'after'),
level8 as(SELECT *
       ,case when sum_quantity > next_quantity THEN 1 ELSE 0 END as flag_quantity
FROm level7
WHERE next_quantity is not null),
level9 as (SELECT *
       ,LEAD(flag_quantity) OVER (partition by customer_id order by order_date) as next_flag_quantity
FROm level8),
level10 as(SELECT *
       ,case when flag_quantity = 1 AND next_flag_quantity = 1 THEN 'yes'
	   ELSE 'no' END as total_flag
FROM level9)
SELECT *
FROm level10
WHERE total_flag = 'yes'

-- 577. «Клієнт з фальшивою лояльністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when sum_chek > next_chek THEN 1 ELSE 0 END as flag_chek
FROM level2),
level4 as(SELECT *
       ,LEAD(flag_chek) OVER (partition by customer_id order by order_date) as next_flag_chek
FROm level3
WHERE next_chek is not null),
level5 as(SELECT *
       ,case when flag_chek = 1 AND next_flag_chek = 1 THEN 'yes'
	   else 'no' END as gradation
FROm level4
WHERE next_flag_chek is not null)
SELECT *
FROm level5
WHERE gradation = 'yes'

-- 578. «Клієнт із зламаною стабільністю»

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
WHERE count_order >= 7),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(avg(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as stddev_chek_first
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as stddev_chek_second
FROM level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
	   ,ROUND((stddev_chek_second / stddev_chek_first)::numeric,2) as diff_stddev
FROM level3)
SELECT *
fROM level4
WHERE diff_chek <= 0.07 AND diff_stddev >= 1.5

-- 579. «Замовлення з фальшивою різноманітністю»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(distinct product_id) as count_unik_prod
FROM level1
GROUP BY customer_id, order_id),
level3 as(SELECT *
       ,sum(quantity) OVER (partition by customer_id, order_id) as quantity_per_order
FROM level1
JOIN level2 USING (customer_id, order_id))
SELECT *
FROM level3
WHERE count_unik_prod = 1 AND quantity_per_order >= 5