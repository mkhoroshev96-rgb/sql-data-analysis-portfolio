-- 613. «Клієнт з інверсією асортименту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(DISTINCT product_id) as count_unik_product
FROm level1
GROUP BY customer_id, order_id, order_date),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / count_unik_product::numeric),2) as avg_quantity_per_product
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level2),
level4 as(SELECT *
       ,ntile(2) OVER (partition by customer_id order by order_date) as ntile_halfs
FROm level3
WHERE count_order >= 8),
level5 as(SELECT customer_id
       ,ROUND(AVG(count_unik_product) FILTER (WHERE ntile_halfs = 1)::numeric,2) as avg_count_unik_prod_first
	   ,ROUND(AVG(count_unik_product) FILTER (WHERE ntile_halfs = 2)::numeric,2) as avg_count_unik_prod_second
	   ,ROUND(AVG(avg_quantity_per_product) FILTER (WHERE ntile_halfs = 1)::numeric,2) as avg_quantity_per_product_first
	   ,ROUND(AVG(avg_quantity_per_product) FILTER (WHERE ntile_halfs = 2)::numeric,2) as avg_quantity_per_product_second
FROm level4
GROUP BY customer_id)
SELECT *
FROm level5
WHERE avg_count_unik_prod_first > avg_count_unik_prod_second AND avg_quantity_per_product_first < avg_quantity_per_product_second

-- 614. "Клієнт з ефектом заміщення лідера кошика"

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
FROm orders
JOIN order_details using(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
	   ,COUNT(product_id) OVER (partition by customer_id, order_id) as count_product
	   ,SUM(quantity) OVER (partition by customer_id, order_id) as sum_quantity_order
FROM level1),
level3 as(SELECT *
       ,ROUND((quantity::numeric / sum_quantity_order::numeric),2) as product_share
FROm level2),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id, order_id order by product_share DESC) as rn_product
FROm level3),
level5 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,LEAD(product_id) OVER (partition by customer_id order by order_date) as next_top_product
	   ,LEAD(count_product) OVER (partition by customer_id order by order_date) as next_count_product
FROm level4
WHERE rn_product = 1),
level6 as(SELECT *
FROM level5
WHERE count_order >= 6 AND next_top_product is not null),
level7 as(SELECT *
       ,ROUND(ABS((next_count_product::numeric - count_product::numeric) / count_product::numeric),2) as diff_count_product
FROM level6)
SELECT *
FROm level7
WHERE product_id <> next_top_product AND diff_count_product <= 0.1

-- 615. «Клієнт з ефектом прихованої цінової компенсації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND((sum(unit_price * quantity)::numeric) / (sum(quantity)::numeric),2) as avg_price
	   ,ROUND((sum(unit_price * quantity)::numeric),2) as order_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(avg_price) OVER (partition by customer_id order by order_date) as next_avg_price
	   ,LEAD(order_chek) OVER (partition by customer_id order by order_date) as next_order_chek
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
FROM level2
WHERE next_avg_price is not null AND next_order_chek is not null),
level4 as(SELECT *
       ,ROUND(ABS((next_order_chek - order_chek) / order_chek)::numeric,2) as diff_order_chek
FROm level3),
level5 as(SELECT *
       ,case when next_avg_price > avg_price AND diff_order_chek <= 0.05 THEN 1
	   ELSE 0 END as flag_price_chek
FROm level4),
level6 as(SELECT *
       ,SUM(flag_price_chek) OVER (partition by customer_id) as sum_flag_price_chek
FROM level5)
SELECT *
FROM level6
WHERE sum_flag_price_chek >= 2

-- 616. «Клієнт з ефектом цінової інерції»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND((SUM(unit_price * quantity)::numeric) / (SUM(quantity)::numeric),2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(avg_price,1) OVER (partition by customer_id order by order_date) as next_1_price
	   ,LEAD(avg_price,2) OVER (partition by customer_id order by order_date) as next_2_price
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,GREATEST(avg_price, next_1_price, next_2_price) as max_price_row
	   ,LEAST(avg_price, next_1_price, next_2_price) as min_price_row
FROM level2
WHERE next_2_price is not null),
level4 as(SELECT *
       ,ROUND((max_price_row / min_price_row)::numeric,2) as diff_max_min
FROm level3),
level5 as(SELECT *
       ,case when diff_max_min <= 1.1 THEN 1 ELSE 0 END as flag_max_min
FROm level4),
level6 as(SELECT *
       ,LEAD(diff_max_min,1) OVER (partition by customer_id order by order_date) as diff_max_min_1
	   ,LEAD(diff_max_min,2) OVER (partition by customer_id order by order_date) as diff_max_min_2
	   ,LEAD(diff_max_min,3) OVER (partition by customer_id order by order_date) as diff_max_min_3
FROm level5),
level7 as(SELECT *
       ,case when diff_max_min_1 > 1.1 AND diff_max_min_2 > 1.1 AND diff_max_min_3 > 1.1 THEN 1
	   ELSE 0 END total_flag
FROM level6
WHERE flag_max_min = 1 AND diff_max_min_3 is not null),
level8 as(SELECT *
       ,SUM(total_flag) OVER (partition by customer_id) as sum_total_flag
FROM level7)
SELECT *
FROm level8
WHERE sum_total_flag >= 1

-- 617. «Клієнт з ефектом відкладеного реагування»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LEAD(avg_discount) OVER (partition by customer_id order by order_date) as next_avg_discount
	   ,LEAD(avg_price,1) OVER (partition by customer_id order by order_date) as next_1_avg_price
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when next_avg_discount >= 2 * avg_discount THEN 1
	   ELSE 0 END as flag_discount
	   ,LEAD(avg_price,2) OVER (partition by customer_id order by order_date) as next_2_avg_price
	   ,LEAD(avg_price,3) OVER (partition by customer_id order by order_date) as next_3_avg_price
FROm level2),
level4 as(SELECT *
       ,ROUND(ABS((next_1_avg_price - avg_price) / avg_price)::numeric,2) as diff_next_1
	   ,ROUND(ABS((next_2_avg_price - avg_price) / avg_price)::numeric,2) as diff_next_2
	   ,ROUND(ABS((next_3_avg_price - avg_price) / avg_price)::numeric,2) as diff_next_3
FROm level3),
level5 as(SELECT *
       ,case when diff_next_1 < 0.1 AND diff_next_2 >= 0.1 AND diff_next_3 >= 0.1 THEN 1
	   ELSE 0 END as total_flag
FROm level4
WHERE next_3_avg_price is not null AND flag_discount = 1),
level6 as(SELECT *
       ,SUM(total_flag) OVER (partition by customer_id) as sum_total_flag
FROm level5)
SELECT *
FROM level6
WHERE sum_total_flag >= 1

-- 618. «Клієнт з ефектом вибіркової памʼяті»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,shipped_date - order_date as delivery_time
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ntile(4) OVER (partition by customer_id order by delivery_time) as ntile_delivery
FROm level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,case when ntile_delivery = 1 THEN 'good_exp'
	   when ntile_delivery = 4 THEN 'bad_exp'
	   else 'other' END as gradation
FROm level2),
level4 as(SELECT *
       ,LEAD(order_chek,1) OVER (partition by customer_id order by order_date) as next_1_order_chek
	   ,LEAD(order_chek,2) OVER (partition by customer_id order by order_date) as next_2_order_chek
FROm level3),
level5 as(SELECT *
       ,case when gradation ='good_exp' AND next_1_order_chek > order_chek AND next_2_order_chek > order_chek THEN 1
	   ELSE 0 END as flag_good_exp
	   ,case when gradation = 'bad_exp' AND next_1_order_chek <= order_chek AND next_2_order_chek <= order_chek THEN 1
	   ELSE 0 END as flag_bad_exp
FROm level4
WHERE next_2_order_chek is not null),
level6 as(SELECT *
       ,SUM(flag_good_exp) OVER (partition by customer_id) as sum_flag_good_exp
	   ,SUM(flag_bad_exp) OVER (partition by customer_id) as sum_flag_bad_exp
FROm level5)
SELECT *
FROM level6
WHERE sum_flag_good_exp >= 1 AND sum_flag_bad_exp  >= 1